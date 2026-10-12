import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { TextDecoder } from 'node:util';
import {
  hasRunLogEvent,
  mdLineSpan,
  normalizeSha256,
  reachedState,
  sha256,
  sourceFilePath,
} from './check-helpers.ts';
import {
  CANDIDATE_STATES,
  CARRY_STATES,
  INTERNAL_AMBIGUITY_FORMAT,
  PROCEDURAL_ACTIONS,
  RESOLUTION_STATES,
  SEARCH_SCOPE_KINDS,
  T5_1_HEADER,
  T5_2_HEADER,
  T5_3_HEADER,
  ambiguityReviewSubjectDigest,
  buildProceduralAuthorityLedgerRow,
  CLOSURE_PHASES,
  closurePhases,
  materialImpactSubjectDigest,
  materialImpactSubjectJson,
  materialImpactSubjectProblems,
  nextClosurePhase,
  operativeScopeProblems,
  parseCandidateRefs,
  parseInternalAmbiguities,
  parseOrderedIds,
  parseStructuredVerifierRecord,
  resolvePinnedCoreRequirement,
  searchBasisDigest,
  sha256Digest,
  tableLooksLike,
  validateProceduralAuthorityRequest,
  validateProceduralAuthorityResponse,
  type AmbiguityReviewSubject,
  type MaterialImpactSubject,
  type PinnedCoreAuthority,
  type ProceduralAuthorityRequest,
  type ProceduralAuthorityResponse,
  type SearchBasis,
  type T5_1Row,
  type T5_2Row,
  legalResolutionCarryState,
} from './internal-ambiguity.ts';
import { lineageCurrentClaimIds, lineageCurrentPacketIds } from './lineage.ts';
import { findTables, normalizeHeader } from './markdown.ts';
import { parseRelations } from './relations.ts';
import type { ResultCollector } from './results.ts';
import {
  SUPPORTED_RUN_FORMAT_VERSIONS,
  usesInternalAmbiguityLifecycle,
  type RunDocument,
  type RunModel,
} from './run-model.ts';

interface Verdict {
  target: string;
  verdict: string;
  valid: boolean;
  path: string;
}

function verdictFromDocument(document: RunDocument): Verdict {
  try {
    const parsed = parseStructuredVerifierRecord(
      Buffer.from(document.text, 'utf8'),
      document.relativePath,
    );
    return {
      target: parsed.target,
      verdict: parsed.verdict,
      valid: true,
      path: document.relativePath,
    };
  } catch {
    const tables = findTables(document.tables, ['field', 'value']);
    const values = new Map<string, string[]>();
    for (const table of tables) {
      for (const row of table.rows) {
        const field = normalizeHeader(row.cells[0] || '');
        if (field !== 'target' && field !== 'verdict') continue;
        const bucket = values.get(field) || [];
        bucket.push((row.cells[1] || '').trim());
        values.set(field, bucket);
      }
    }
    return {
      target: values.get('target')?.[0] || '',
      verdict: values.get('verdict')?.[0] || '',
      valid: false,
      path: document.relativePath,
    };
  }
}

function ambiguitySignals(model: RunModel): string[] {
  const signals: string[] = [];
  for (const document of model.documents.values()) {
    if (!document) continue;
    if (document.relativePath === 'ledgers/internal-ambiguities.md') signals.push(document.relativePath);
    if (/internal_ambiguity_format\s*:/u.test(document.text)) signals.push('format marker');
    if (document.tables.some((table) => tableLooksLike(table, 'ambiguity_id'))) signals.push('T5 table');
  }
  return [...new Set(signals)];
}

function exactPositive(value: string): number | null {
  return /^[1-9]\d*$/u.test(value) && Number.isSafeInteger(Number(value)) ? Number(value) : null;
}

function locatorSpan(path: string, locator: string): { start: number; end: number; bytes: Buffer } | null {
  const match = locator.match(/^L([1-9]\d*)-L([1-9]\d*)$/u);
  if (!match) return null;
  const span = mdLineSpan(path, Number(match[1]), Number(match[2]));
  return span?.bytes && span.startByte !== null && span.endByte !== null
    ? { start: span.startByte, end: span.endByte, bytes: span.bytes }
    : null;
}

function canonicalBase64(raw: string): Buffer | null {
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(raw)) return null;
  const bytes = Buffer.from(raw, 'base64');
  return bytes.toString('base64') === raw ? bytes : null;
}

function exactUtf8(bytes: Buffer): boolean {
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    return true;
  } catch {
    return false;
  }
}

function verdictFor(model: RunModel, id: string): Verdict | null {
  const matches: Verdict[] = [];
  for (const document of model.documents.values()) {
    if (!document?.relativePath.startsWith('verification/harness/')) continue;
    if (basename(document.relativePath) !== `${id}.md`) continue;
    matches.push(verdictFromDocument(document));
  }
  return matches.length === 1 ? matches[0] : null;
}

function verdictForTarget(model: RunModel, target: string): Verdict | null {
  const matches: Verdict[] = [];
  for (const document of model.documents.values()) {
    if (!document?.relativePath.startsWith('verification/harness/')) continue;
    if (!/^VER-\d{4,}\.md$/u.test(basename(document.relativePath))) continue;
    const verdict = verdictFromDocument(document);
    if (verdict.target === target) matches.push(verdict);
  }
  return matches.length === 1 ? matches[0] : null;
}

function sourceRow(model: RunModel, id: string) {
  return model.corpus.sources.find((row) => row.values.sourceId === id) || null;
}

function sourceBytes(model: RunModel, id: string): { path: string; bytes: Buffer } | null {
  const source = sourceRow(model, id);
  if (!source) return null;
  const path = sourceFilePath(model.runDir, source.values.locus);
  return path && existsSync(path) ? { path, bytes: readFileSync(path) } : null;
}

function sameSourceEntity(model: RunModel, row: T5_1Row): boolean {
  if (row.values.sourceEntityKind === 'PKT') {
    return model.packets.some((packet) => (
      packet.values.packetId === row.values.sourceEntityId
      && packet.values.sourceId === row.values.sourceId
    ));
  }
  if (row.values.sourceEntityKind === 'CC') {
    return model.claims.some((claim) => (
      claim.values.claimId === row.values.sourceEntityId
      && claim.values.sources.split(',').map((part) => part.trim()).includes(row.values.sourceId)
    ));
  }
  return false;
}

function materialIdOrder(id: string): [number, bigint] {
  const match = id.match(/^(PKT|CC|REL)-(\d{4,})$/u);
  return match
    ? [['PKT', 'CC', 'REL'].indexOf(match[1]), BigInt(match[2])]
    : [99, BigInt('999999999999999999999999999999999999')];
}

function compareMaterialIds(left: string, right: string): number {
  const a = materialIdOrder(left);
  const b = materialIdOrder(right);
  if (a[0] !== b[0]) return a[0] - b[0];
  return a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0;
}

function validateReviewedUnaffectedIds(
  subject: MaterialImpactSubject,
  currentPackets: ReadonlySet<string>,
  currentClaims: ReadonlySet<string>,
  relationIds: ReadonlySet<string>,
  fail: (message: string) => void,
  label: string,
): void {
  const values = subject.reviewed_unaffected_ids;
  if (!Array.isArray(values)) {
    fail(`${label} reviewed_unaffected_ids must be an array`);
    return;
  }
  if (new Set(values).size !== values.length) {
    fail(`${label} reviewed_unaffected_ids contains duplicates`);
  }
  if (values.some((id) => typeof id !== 'string' || !/^(?:PKT|CC|REL)-\d{4,}$/u.test(id))) {
    fail(`${label} reviewed_unaffected_ids contains prose or an illegal ID kind`);
  }
  for (let index = 1; index < values.length; index += 1) {
    if (compareMaterialIds(values[index - 1], values[index]) >= 0) {
      fail(`${label} reviewed_unaffected_ids is not in canonical order`);
      break;
    }
  }
  const affected = new Set(subject.operative_scope.affected_ids);
  for (const id of values) {
    if (affected.has(id)) {
      fail(`${label} reviewed_unaffected_ids overlaps operative_scope.affected_ids at ${id}`);
    }
    if (id.startsWith('PKT-') && !currentPackets.has(id)) {
      fail(`${label} reviewed_unaffected_ids packet ${id} is absent or historical`);
    } else if (id.startsWith('CC-') && !currentClaims.has(id)) {
      fail(`${label} reviewed_unaffected_ids claim ${id} is absent or historical`);
    } else if (id.startsWith('REL-') && !relationIds.has(id)) {
      fail(`${label} reviewed_unaffected_ids relation ${id} is absent`);
    }
  }
}

function validateSourceLocators(
  model: RunModel,
  sourceId: string,
  subject: MaterialImpactSubject,
  fail: (message: string) => void,
  label: string,
): void {
  const values = subject.source_locators;
  if (!Array.isArray(values)) {
    fail(`${label} source_locators must be an array`);
    return;
  }
  let previous: [number, number] | null = null;
  for (const value of values) {
    if (typeof value !== 'string') {
      fail(`${label} source_locators contains non-string prose`);
      continue;
    }
    const match = value.match(/^(SRC-\d{4,}):L([1-9]\d*)-L([1-9]\d*)$/u);
    if (!match) {
      fail(`${label} source locator ${value || '(blank)'} is malformed`);
      continue;
    }
    const start = Number(match[2]);
    const end = Number(match[3]);
    if (match[1] !== sourceId) {
      fail(`${label} source locator ${value} crosses the bound frozen source`);
      continue;
    }
    const source = sourceRow(model, sourceId);
    const path = source ? sourceFilePath(model.runDir, source.values.locus) : null;
    if (!source || source.values.scheme.replace(/`/gu, '').trim() !== 'md-lines'
      || !path || !locatorSpan(path, `L${String(start)}-L${String(end)}`)) {
      fail(`${label} source locator ${value} does not reopen an existing exact Core locus`);
    }
    if (end < start) fail(`${label} source locator ${value} is malformed`);
    const order: [number, number] = [start, end];
    if (previous && (previous[0] > order[0]
      || (previous[0] === order[0] && previous[1] >= order[1]))) {
      fail(`${label} source_locators is not in deterministic order`);
    }
    previous = order;
  }
}

function localScopeRefs(model: RunModel, row: T5_2Row): string[] | null {
  try {
    const value = JSON.parse(row.values.searchCompletionRef) as unknown;
    if (!Array.isArray(value) || value.length === 0
      || value.some((id) => typeof id !== 'string' || !/^WLK-\d{4,}$/u.test(id))
      || JSON.stringify(value) !== row.values.searchCompletionRef
      || new Set(value).size !== value.length) return null;
    const order = new Map(model.sourceWalk.intervals.map((interval, index) => [interval.values.walkId, index]));
    if (value.some((id) => !order.has(id))) return null;
    if (value.some((id, index) => index > 0 && order.get(value[index - 1])! >= order.get(id)!)) return null;
    return value;
  } catch {
    return null;
  }
}

function completionRef(model: RunModel, sourceId: string): string | null {
  const completion = model.sourceWalk.completions.find((row) => (
    row.values.sourceId === sourceId && row.values.completionState === 'complete'
  ));
  if (!completion) return null;
  return `${sourceId}@${completion.values.finalCursorId}@${completion.values.sourceHash}`;
}

function reviewSubject(definition: T5_1Row, assessment: T5_2Row): AmbiguityReviewSubject | null {
  const packets = parseOrderedIds(definition.values.basisPacketIds, 'PKT');
  const candidates = parseCandidateRefs(assessment.values.candidateRefs);
  const relations = parseOrderedIds(assessment.values.affectedRelationIds, 'REL', true);
  const start = Number(definition.values.expressionStartByte);
  const end = Number(definition.values.expressionEndByte);
  if (!packets.clean || !candidates.clean || !relations.clean
    || !Number.isSafeInteger(start) || !Number.isSafeInteger(end)) return null;
  return {
    source_entity_kind: definition.values.sourceEntityKind as 'PKT' | 'CC',
    source_entity_id: definition.values.sourceEntityId,
    source_id: definition.values.sourceId,
    expression_locator: definition.values.expressionLocator,
    expression_start_byte: start,
    expression_end_byte: end,
    expression_sha256: definition.values.expressionSha256,
    expression_bytes_base64: definition.values.expressionBytesBase64,
    basis_packet_ids: packets.ids,
    search_scope_kind: assessment.values.searchScopeKind as SearchBasis['scope_kind'],
    search_completion_ref: assessment.values.searchCompletionRef,
    search_basis_digest: assessment.values.searchBasisDigest,
    candidate_state: assessment.values.candidateState as SearchBasis['candidate_state'],
    candidate_refs: candidates.candidates,
    affected_relation_ids: relations.ids,
    resolution_state: assessment.values.resolutionState as AmbiguityReviewSubject['resolution_state'],
    carry_state: assessment.values.carryState as AmbiguityReviewSubject['carry_state'],
    proposed_by: assessment.values.proposedBy,
  };
}

function controlJsonFiles(runDir: string): string[] {
  const directory = join(runDir, 'control/gates');
  return existsSync(directory)
    ? readdirSync(directory).filter((name) => name.endsWith('.json')).sort()
    : [];
}

type ProceduralGateFileKind = 'request' | 'response';

function proceduralGateFileKind(name: string): ProceduralGateFileKind | null {
  if (/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*-request\.json$/u.test(name)) {
    return 'request';
  }
  if (/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*-response\.json$/u.test(name)) {
    return 'response';
  }
  if (/^(?:GATE|RESP)-S4-AMB-/u.test(name)) {
    throw new Error('procedural gate filename does not match the exact Slice 5 identity/path grammar');
  }
  return null;
}

interface AmbiguityControlState {
  requests: Map<string, { value: ProceduralAuthorityRequest; bytes: Buffer }>;
  responses: Map<string, { value: ProceduralAuthorityResponse; bytes: Buffer }>;
  active: number;
  latestRequestIds: Set<string>;
}

function checkControlState(
  model: RunModel,
  fail: (message: string) => void,
): AmbiguityControlState {
  const names = controlJsonFiles(model.runDir);
  const requests = new Map<string, { value: ProceduralAuthorityRequest; bytes: Buffer }>();
  const responses = new Map<string, { value: ProceduralAuthorityResponse; bytes: Buffer }>();
  for (const name of names) {
    try {
      const kind = proceduralGateFileKind(name);
      if (kind === null) continue;
      const path = join(model.runDir, 'control/gates', name);
      const bytes = readFileSync(path);
      const value = JSON.parse(bytes.toString('utf8')) as unknown;
      if (kind === 'request') {
        const request = value as ProceduralAuthorityRequest;
        const canonical = validateProceduralAuthorityRequest(request);
        if (!canonical.equals(bytes)) fail(`${name} is not exact canonical request bytes`);
        if (name !== `${request.request_id}-request.json`) fail(`${name} request identity/path mismatch`);
        if (requests.has(request.request_id)) fail(`${request.request_id} request identity is duplicated`);
        requests.set(request.request_id, { value: request, bytes });
      } else {
        const response = value as ProceduralAuthorityResponse;
        if (responses.has(response.request_id)) fail(`${response.request_id} response identity is duplicated`);
        responses.set(response.request_id, { value: response, bytes });
      }
    } catch (error) {
      fail(`${name} is invalid: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  const latestByAssessment = new Map<string, { id: string; sequence: number }>();
  for (const [id, request] of requests) {
    const sequence = Number(id.match(/-Q([1-9]\d*)$/u)?.[1] || '0');
    const key = `${request.value.ambiguity_id}\0${String(request.value.assessment_seq)}`;
    const prior = latestByAssessment.get(key);
    if (!prior || sequence > prior.sequence) latestByAssessment.set(key, { id, sequence });
  }
  const latestRequestIds = new Set([...latestByAssessment.values()].map((entry) => entry.id));
  let active = 0;
  for (const [id, request] of requests) {
    const response = responses.get(id);
    if (!response) {
      if (latestRequestIds.has(id)) active += 1;
      continue;
    }
    try {
      const bytes = validateProceduralAuthorityResponse(request.value, request.bytes, response.value);
      const path = join(model.runDir, 'control/gates', `${id}-response.json`);
      if (!existsSync(path) || !bytes.equals(response.bytes) || !bytes.equals(readFileSync(path))) {
        fail(`${id} response is not exact canonical retained bytes`);
      }
    } catch (error) {
      fail(`${id} response is invalid: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  for (const id of responses.keys()) if (!requests.has(id)) fail(`${id} has a fabricated or orphan response`);
  if (active > 1) fail(`at most one active internal-ambiguity request is legal; found ${active}`);
  return { requests, responses, active, latestRequestIds };
}

export function runK2Ambiguities(
  results: ResultCollector,
  model: RunModel,
  pinnedCoreAuthority?: PinnedCoreAuthority,
): void {
  results.run('K2.17', 'internal ambiguity lifecycle structure (STRUCTURAL ONLY)', (fail) => {
    const version = model.manifest?.runFormatVersion || '';
    const active = usesInternalAmbiguityLifecycle(version);
    const signals = ambiguitySignals(model);
    const ambiguity = parseInternalAmbiguities(model);
    if (!active) {
      if (signals.length > 0) fail(`run format ${version || '(pre-versioned)'} must reject active 1.5 ambiguity artifacts`);
      if (version && !(SUPPORTED_RUN_FORMAT_VERSIONS as readonly string[]).includes(version)) {
        fail(`ambiguity activation cannot determine unsupported run_format_version "${version}"`);
      }
      return `internal ambiguity lifecycle is not applicable to run format ${version || '(pre-versioned)'}`;
    }

    const phases = closurePhases(model.runLog);
    const retainedPhaseLines = model.runLog?.lines.filter((line) => /^\s*closure_phase\s*:/u.test(line)) || [];
    if (retainedPhaseLines.length !== phases.length) fail('closure_phase contains an unknown value');
    if (phases.some((phase, index) => phase !== CLOSURE_PHASES[index])) {
      fail('retained closure phases are duplicated, skipped, or out of order');
    } else if (phases.length < CLOSURE_PHASES.length) {
      try { nextClosurePhase(phases); }
      catch (error) { fail(error instanceof Error ? error.message : String(error)); }
    }
    const hasC1 = phases.includes('S4-C1-relations-closed');
    const hasC2 = phases.includes('S4-C2-ambiguities-finalized');
    const hasC3 = phases.includes('S4-C3-exit');
    const hasS5 = hasRunLogEvent(model.runLog, 'S5', 'entry');
    if ((hasC2 || hasC3 || hasS5) && !hasC1) fail('C2, C3, and S5 require retained C1');
    if ((hasC3 || hasS5) && !hasC2) fail('C3 and S5 require retained C2');
    if (hasS5 && !hasC3) fail('S5 requires retained C3');
    const relations = parseRelations(model);
    if (hasC1 && (!relations.document || relations.rows.length === 0)) {
      fail('C1 marker requires a complete nonempty canonical relations artifact');
    }

    if (!ambiguity.document) {
      if (hasC2 || hasC3 || hasS5 || signals.length > 0) {
        fail('run format 1.5 requires ledgers/internal-ambiguities.md at C2, C3, and S5');
      }
      return '1.5 ambiguity artifact is not required before C2';
    }
    const markerCount = ambiguity.document.lines.filter((line) => (
      /^\s*-\s*internal[_ -]ambiguity[_ -]format\s*:/iu.test(line)
    )).length;
    if (markerCount !== 1 || ambiguity.format !== INTERNAL_AMBIGUITY_FORMAT) {
      fail(`internal_ambiguity_format must equal ${INTERNAL_AMBIGUITY_FORMAT} exactly once`);
    }
    const ambiguityTables = ambiguity.document.tables.filter((table) => tableLooksLike(table, 'ambiguity_id'));
    if (ambiguityTables.length !== 3 || ambiguity.t5_1Tables.length !== 1
      || ambiguity.t5_2Tables.length !== 1 || ambiguity.t5_3Tables.length !== 1) {
      fail('internal ambiguity artifact requires exactly three canonical T5.1/T5.2/T5.3 tables');
    }
    for (const [table, expected] of [
      [ambiguity.t5_1Tables[0], T5_1_HEADER],
      [ambiguity.t5_2Tables[0], T5_2_HEADER],
      [ambiguity.t5_3Tables[0], T5_3_HEADER],
    ] as const) {
      if (table && table.normalizedHeader.join('\0') !== expected.map(normalizeHeader).join('\0')) {
        fail('T5 canonical column ordering is invalid');
      }
    }
    if (!hasC1 && (ambiguity.t5_1Rows.length || ambiguity.t5_2Rows.length || ambiguity.t5_3Rows.length)) {
      fail('canonical ambiguity rows are forbidden before C1 closes the relation basis');
    }

    const currentPackets = lineageCurrentPacketIds(model);
    const currentClaims = lineageCurrentClaimIds(model);
    const definitions = new Map<string, T5_1Row>();
    const expressionKeys = new Set<string>();
    for (const row of ambiguity.t5_1Rows) {
      const values = row.values;
      if (!/^AMB-\d{4,}$/u.test(values.ambiguityId)) fail(`${values.ambiguityId || 'T5.1 row'} has invalid ambiguity_id`);
      if (definitions.has(values.ambiguityId)) fail(`${values.ambiguityId} is defined more than once`);
      else definitions.set(values.ambiguityId, row);
      if (!sameSourceEntity(model, row)) fail(`${values.ambiguityId} source entity is absent or not from ${values.sourceId}`);
      if (values.sourceEntityKind === 'PKT' && !currentPackets.has(values.sourceEntityId)) fail(`${values.ambiguityId} source packet is historical`);
      if (values.sourceEntityKind === 'CC' && !currentClaims.has(values.sourceEntityId)) fail(`${values.ambiguityId} source claim is historical`);
      const source = sourceBytes(model, values.sourceId);
      const start = Number(values.expressionStartByte);
      const end = Number(values.expressionEndByte);
      if (!source || !/^\d+$/u.test(values.expressionStartByte) || !/^\d+$/u.test(values.expressionEndByte)
        || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end <= start
        || end > (source?.bytes.length || 0)) {
        fail(`${values.ambiguityId} expression interval is invalid`);
        continue;
      }
      const expression = source.bytes.subarray(start, end);
      if (!exactUtf8(expression)) fail(`${values.ambiguityId} interval is not on valid UTF-8 boundaries`);
      const decoded = canonicalBase64(values.expressionBytesBase64);
      if (!decoded || !decoded.equals(expression)) fail(`${values.ambiguityId} expression base64 does not reopen exact bytes`);
      if (normalizeSha256(values.expressionSha256) !== sha256(expression)) fail(`${values.ambiguityId} expression hash is wrong`);
      const locus = locatorSpan(source.path, values.expressionLocator);
      if (!locus || start < locus.start || end > locus.end) fail(`${values.ambiguityId} expression locator does not contain the interval`);
      const expressionKey = `${values.sourceId}\0${start}\0${end}\0${values.expressionSha256}`;
      if (expressionKeys.has(expressionKey)) fail(`${values.ambiguityId} duplicates an exact expression definition`);
      expressionKeys.add(expressionKey);
      const packets = parseOrderedIds(values.basisPacketIds, 'PKT');
      if (!packets.clean) fail(`${values.ambiguityId} basis_packet_ids are not canonical`);
      let covered = false;
      for (const id of packets.ids) {
        const packet = model.packets.find((candidate) => candidate.values.packetId === id);
        if (!packet || packet.values.sourceId !== values.sourceId || !currentPackets.has(id)) {
          fail(`${values.ambiguityId} basis packet ${id} is absent, cross-source, or historical`);
          continue;
        }
        const packetSpan = locatorSpan(source.path, packet.values.locator);
        if (packetSpan && start >= packetSpan.start && end <= packetSpan.end) covered = true;
      }
      if (!covered) fail(`${values.ambiguityId} basis packets do not cover the expression interval`);
      if (!/^(?:human|invocation):\S+$/u.test(values.detectedBy)
        || /^human:(?:authority|operator)(?:$|[-_:])/iu.test(values.detectedBy)) {
        fail(`${values.ambiguityId} detector identity is invalid or authority-owned`);
      }
    }

    const assessments = new Map<string, T5_2Row[]>();
    const reviewDigests = new Set<string>();
    const relationIds = new Set(relations.rows.map((row) => row.values.relationId));
    for (const row of ambiguity.t5_2Rows) {
      const values = row.values;
      const definition = definitions.get(values.ambiguityId);
      if (!definition) { fail(`${values.ambiguityId || 'T5.2 row'} has no T5.1 definition`); continue; }
      const bucket = assessments.get(values.ambiguityId) || [];
      bucket.push(row); assessments.set(values.ambiguityId, bucket);
      const seq = exactPositive(values.assessmentSeq);
      const expectedPredecessor = seq === 1 ? 'none' : String((seq || 0) - 1);
      if (!seq || values.predecessorAssessmentSeq !== expectedPredecessor) fail(`${values.ambiguityId} assessment predecessor is invalid`);
      if (!(SEARCH_SCOPE_KINDS as readonly string[]).includes(values.searchScopeKind)) fail(`${values.ambiguityId} search_scope_kind is invalid`);
      if (!(CANDIDATE_STATES as readonly string[]).includes(values.candidateState)) fail(`${values.ambiguityId} candidate_state is invalid`);
      if (!(RESOLUTION_STATES as readonly string[]).includes(values.resolutionState)) fail(`${values.ambiguityId} resolution_state is invalid`);
      if (!(CARRY_STATES as readonly string[]).includes(values.carryState)) fail(`${values.ambiguityId} carry_state is invalid`);
      if (values.searchSourceId !== definition.values.sourceId) fail(`${values.ambiguityId} search source crosses the frozen source`);
      const candidates = parseCandidateRefs(values.candidateRefs);
      if (!candidates.clean) fail(`${values.ambiguityId} candidate_refs: ${candidates.error || 'invalid'}`);
      const count = candidates.candidates.length;
      if ((values.candidateState === 'single' && count !== 1)
        || (values.candidateState === 'multiple' && count < 2)
        || (values.candidateState.startsWith('null-') && count !== 0)) {
        fail(`${values.ambiguityId} candidate_state/count mismatch`);
      }
      const source = sourceBytes(model, definition.values.sourceId);
      for (const candidate of candidates.candidates) {
        if (candidate.kind === 'PKT') {
          const packet = model.packets.find((entry) => entry.values.packetId === candidate.id);
          if (!packet || packet.values.sourceId !== definition.values.sourceId || !currentPackets.has(candidate.id)) {
            fail(`${values.ambiguityId} candidate ${candidate.id} is absent, cross-source, or historical`);
          }
        } else if (candidate.source_id !== definition.values.sourceId || !source) {
          fail(`${values.ambiguityId} source-locus candidate crosses the frozen source`);
        } else {
          const span = locatorSpan(source.path, candidate.locator);
          if (!span || sha256Digest(span.bytes) !== candidate.span_hash) {
            fail(`${values.ambiguityId} source-locus candidate does not reopen exact bytes`);
          }
        }
      }
      const scopeRefs = values.searchScopeKind === 'local-intervals'
        ? localScopeRefs(model, row) : [];
      if (values.searchScopeKind === 'local-intervals') {
        if (!scopeRefs || values.candidateState !== 'single' || values.resolutionState !== 'resolved-local') {
          fail(`${values.ambiguityId} local search requires ordered intervals and one resolved candidate`);
        } else if (scopeRefs.some((id) => model.sourceWalk.intervals.find((item) => item.values.walkId === id)?.values.sourceId !== values.searchSourceId)) {
          fail(`${values.ambiguityId} local search interval crosses source`);
        }
      } else if (values.searchCompletionRef !== completionRef(model, values.searchSourceId)) {
        fail(`${values.ambiguityId} full-same-source completion reference is invalid`);
      }
      if (values.resolutionState === 'resolved-local' && (values.candidateState !== 'single' || values.carryState !== 'none')) {
        fail(`${values.ambiguityId} resolved-local requires one candidate and carry none`);
      }
      if (values.resolutionState === 'unresolved' && values.searchScopeKind !== 'full-same-source') {
        fail(`${values.ambiguityId} unresolved assessment requires full-same-source search`);
      }
      const affected = parseOrderedIds(values.affectedRelationIds, 'REL', true);
      if (!affected.clean) fail(`${values.ambiguityId} affected_relation_ids are not canonical`);
      affected.ids.forEach((id) => { if (!relationIds.has(id)) fail(`${values.ambiguityId} affected relation ${id} is absent`); });
      if (!legalResolutionCarryState(
        values.resolutionState,
        values.carryState,
        affected.ids.length,
      )) fail(`${values.ambiguityId} has an illegal resolution/carry/affected-set combination`);
      const packets = parseOrderedIds(definition.values.basisPacketIds, 'PKT');
      const sourceRecord = sourceRow(model, definition.values.sourceId);
      const expressionStart = Number(definition.values.expressionStartByte);
      const expressionEnd = Number(definition.values.expressionEndByte);
      if (sourceRecord && packets.clean && candidates.clean && affected.clean
        && Number.isSafeInteger(expressionStart) && Number.isSafeInteger(expressionEnd)) {
        const basis: SearchBasis = {
          source_id: definition.values.sourceId,
          source_hash: sourceRecord.values.contentHash,
          source_length_bytes: source?.bytes.length || 0,
          scope_kind: values.searchScopeKind as SearchBasis['scope_kind'],
          scope_refs: scopeRefs || [],
          completion_ref: values.searchScopeKind === 'local-intervals' ? 'none' : values.searchCompletionRef,
          expression_start_byte: expressionStart,
          expression_end_byte: expressionEnd,
          expression_sha256: definition.values.expressionSha256,
          basis_packet_ids: packets.ids,
          candidate_state: values.candidateState as SearchBasis['candidate_state'],
          candidate_refs: candidates.candidates,
        };
        if (searchBasisDigest(basis) !== values.searchBasisDigest) fail(`${values.ambiguityId} search_basis_digest is wrong`);
      }
      const subject = reviewSubject(definition, row);
      if (!subject || ambiguityReviewSubjectDigest(subject) !== values.reviewSubjectDigest) {
        fail(`${values.ambiguityId} review_subject_digest is wrong`);
      }
      if (reviewDigests.has(values.reviewSubjectDigest)) fail(`${values.ambiguityId} duplicates a review-subject digest`);
      reviewDigests.add(values.reviewSubjectDigest);
      if (!/^VER-\d{4,}$/u.test(values.reviewedBy)) fail(`${values.ambiguityId} reviewed_by is invalid`);
      const verdict = verdictFor(model, values.reviewedBy);
      const target = `internal-ambiguity-review-subject:${values.reviewSubjectDigest}`;
      if (!verdict?.valid || verdict.target !== target || verdict.verdict !== 'upheld') {
        fail(`${values.ambiguityId} requires one fresh upheld verifier bound to ${target}`);
      }
      if (!/^(?:human|invocation):\S+$/u.test(values.proposedBy)) fail(`${values.ambiguityId} proposed_by is invalid`);
    }
    for (const [id, rows] of assessments) {
      const sequences = rows.map((row) => Number(row.values.assessmentSeq)).sort((a, b) => a - b);
      if (sequences.some((value, index) => value !== index + 1)) fail(`${id} assessment history is forked or noncontiguous`);
      rows.sort((left, right) => (
        Number(left.values.assessmentSeq) - Number(right.values.assessmentSeq)
      ));
    }
    if (hasC2) {
      for (const id of definitions.keys()) if (!assessments.has(id)) fail(`${id} has no reviewed T5.2 assessment at C2`);
    }

    interface RetainedMaterialImpact {
      subject: MaterialImpactSubject;
      digest: string;
      subjectRef: string;
      reviewRef: string;
      verdict: string;
    }
    const materialHistories = new Map<string, RetainedMaterialImpact[]>();
    for (const file of model.files.filter((entry) => (
      /^verification\/harness\/S4\/material-impact-subjects\/AMB-\d{4,}-A\d+-M\d+\.json$/u
        .test(entry.relativePath)
    ))) {
      try {
        const subject = JSON.parse(file.text) as MaterialImpactSubject;
        const match = file.relativePath.match(/\/(AMB-\d{4,})-A(\d+)-M(\d+)\.json$/u);
        if (!match
          || subject.ambiguity_id !== match[1]
          || subject.assessment_seq !== Number(match[2])
          || subject.material_impact_seq !== Number(match[3])) {
          fail(`${file.relativePath} identity does not match its canonical path`);
        }
        if (materialImpactSubjectJson(subject) !== file.text) {
          fail(`${file.relativePath} is not exact canonical compact JSON`);
        }
        materialImpactSubjectProblems(subject)
          .forEach((problem) => fail(`${file.relativePath}: ${problem}`));
        const assessment = assessments.get(subject.ambiguity_id)?.find((row) => (
          Number(row.values.assessmentSeq) === subject.assessment_seq
        ));
        if (!assessment || assessment.values.resolutionState !== 'unresolved') {
          fail(`${file.relativePath} does not bind one unresolved T5.2 assessment`);
        } else {
          const expectedAssessmentRef = `internal-ambiguity:T5.2:${subject.ambiguity_id}:A${String(subject.assessment_seq)}@${sha256Digest(assessment.raw)}`;
          if (subject.t5_2_assessment_ref !== expectedAssessmentRef
            || subject.t5_2_review_subject_digest !== assessment.values.reviewSubjectDigest) {
            fail(`${file.relativePath} T5.2 row or review-subject binding is stale`);
          }
          const ambiguityVerdict = verdictFor(model, assessment.values.reviewedBy);
          const ambiguityVerdictFile = ambiguityVerdict
            ? model.files.find((entry) => entry.relativePath === ambiguityVerdict.path)
            : null;
          const expectedReviewRef = ambiguityVerdictFile
            ? `ambiguity-review-verdict:${assessment.values.reviewedBy}@${sha256Digest(ambiguityVerdictFile.text)}`
            : '';
          if (!ambiguityVerdict?.valid || ambiguityVerdict.verdict !== 'upheld'
            || subject.t5_2_review_ref !== expectedReviewRef) {
            fail(`${file.relativePath} does not bind the exact upheld ambiguity-review bytes`);
          }
          const affected = parseOrderedIds(assessment.values.affectedRelationIds, 'REL', true);
          const expectedC1 = affected.ids.length > 0
            ? 'relations-basis:closure_phase=S4-C1-relations-closed;artifact=ledgers/relations.md'
            : 'none';
          if (subject.c1_relation_basis_ref !== expectedC1) {
            fail(`${file.relativePath} C1 relation basis reference is wrong`);
          }
          validateReviewedUnaffectedIds(
            subject,
            currentPackets,
            currentClaims,
            relationIds,
            fail,
            file.relativePath,
          );
          validateSourceLocators(
            model,
            definitions.get(subject.ambiguity_id)?.values.sourceId || '',
            subject,
            fail,
            file.relativePath,
          );
          for (const row of subject.operative_scope.impact_rows) {
            if (!pinnedCoreAuthority) {
              fail(`${file.relativePath} requirement_ref resolution requires verified run-pinned Core authority`);
              continue;
            }
            try {
              resolvePinnedCoreRequirement(pinnedCoreAuthority, row.requirement_ref);
            } catch (error) {
              fail(`${file.relativePath} requirement_ref ${row.requirement_ref} does not resolve under the run pin: ${
                error instanceof Error ? error.message : String(error)
              }`);
            }
          }
        }
        const digest = materialImpactSubjectDigest(subject);
        const review = verdictForTarget(
          model,
          `internal-ambiguity-material-impact-review-subject:${digest}`,
        );
        const reviewFile = review
          ? model.files.find((entry) => entry.relativePath === review.path)
          : null;
        const reviewId = review ? basename(review.path, '.md') : '';
        const reviewRef = reviewFile
          ? `material-impact-verdict:${reviewId}@${sha256Digest(reviewFile.text)}`
          : '';
        if (!review?.valid || !['upheld', 'refuted', 'cannot-determine'].includes(review.verdict)) {
          fail(`${file.relativePath} has no exact fresh material-impact verdict`);
        }
        const key = `${subject.ambiguity_id}\0${String(subject.assessment_seq)}`;
        const history = materialHistories.get(key) || [];
        history.push({
          subject,
          digest,
          subjectRef: `material-impact-subject:${subject.ambiguity_id}:A${String(subject.assessment_seq)}:M${String(subject.material_impact_seq)}@${digest}`,
          reviewRef,
          verdict: review?.verdict || '',
        });
        materialHistories.set(key, history);
      } catch (error) {
        fail(`${file.relativePath} is malformed: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    const latestMaterial = new Map<string, RetainedMaterialImpact>();
    for (const [key, history] of materialHistories) {
      history.sort((left, right) => (
        left.subject.material_impact_seq - right.subject.material_impact_seq
      ));
      if (history.some((entry, index) => entry.subject.material_impact_seq !== index + 1)) {
        fail(`${key.replace('\0', ' A')} material-impact M history is forked or noncontiguous`);
      }
      const latest = history.at(-1);
      if (latest) latestMaterial.set(key, latest);
      if (latest && latest.verdict !== 'upheld') {
        fail(`${key.replace('\0', ' A')} latest material-impact verdict must be upheld to continue`);
      }
    }
    if (hasC2) {
      for (const [id, rows] of assessments) {
        const latestAssessment = rows.at(-1);
        if (!latestAssessment || latestAssessment.values.resolutionState !== 'unresolved') continue;
        const key = `${id}\0${latestAssessment.values.assessmentSeq}`;
        if (!materialHistories.has(key)) {
          fail(`${id} latest unresolved T5.2 assessment has no material-impact history at C2`);
        } else if (!latestMaterial.has(key)) {
          fail(`${id} latest unresolved T5.2 assessment has no usable material-impact head at C2`);
        }
      }
    }

    const control = checkControlState(model, fail);
    const requestSeqs = new Map<string, number[]>();
    for (const request of control.requests.values()) {
      const value = request.value;
      const current = assessments.get(value.ambiguity_id)?.at(-1);
      const requestSeq = Number(value.request_id.match(/-Q([1-9]\d*)$/u)?.[1] || '0');
      const key = `${value.ambiguity_id}\0${String(value.assessment_seq)}`;
      const bucket = requestSeqs.get(key) || [];
      bucket.push(requestSeq);
      requestSeqs.set(key, bucket);
      if (!current || value.assessment_seq !== Number(current.values.assessmentSeq)
        || current.values.resolutionState !== 'unresolved'
        || value.authority_subject.t5_2_review_subject_digest !== current.values.reviewSubjectDigest
        || value.authority_subject.candidate_state !== current.values.candidateState
        || JSON.stringify(value.authority_subject.candidate_refs) !== current.values.candidateRefs
        || value.authority_subject.carry_state !== current.values.carryState
        || value.authority_subject.affected_relation_ids.join(', ')
          !== (current.values.affectedRelationIds === 'none' ? '' : current.values.affectedRelationIds)) {
        fail(`${value.request_id} is stale or disagrees with the current unresolved T5.2 basis`);
      }
      const material = materialHistories.get(key)?.find((entry) => (
        entry.subject.material_impact_seq === value.authority_subject.material_impact_seq
      ));
      if (!material || material.subject.materiality_class !== 'C'
        || material.verdict !== 'upheld'
        || value.authority_subject.material_impact_seq !== material.subject.material_impact_seq
        || value.authority_subject.material_impact_subject_ref !== material.subjectRef
        || value.authority_subject.material_impact_review_ref !== material.reviewRef
        || value.authority_subject.materiality_class !== material.subject.materiality_class
        || JSON.stringify(value.authority_subject.operative_scope)
          !== JSON.stringify(material.subject.operative_scope)
        || JSON.stringify(value.authority_subject.source_locators)
          !== JSON.stringify(material.subject.source_locators)
        || JSON.stringify(value.authority_subject.reviewed_unaffected_ids)
          !== JSON.stringify(material.subject.reviewed_unaffected_ids)
        || value.authority_subject.unresolved_statement !== material.subject.unresolved_statement) {
        fail(`${value.request_id} does not exactly project its upheld Class C material-impact basis`);
      }
      const latest = latestMaterial.get(key);
      if (control.latestRequestIds.has(value.request_id)
        && (!latest || material?.digest !== latest.digest)) {
        fail(`${value.request_id} latest request does not bind the latest upheld material-impact basis`);
      }
    }
    for (const [key, sequences] of requestSeqs) {
      sequences.sort((left, right) => left - right);
      if (sequences.some((value, index) => value !== index + 1)) {
        fail(`${key.replace('\0', ' A')} request Q history is forked or noncontiguous`);
      }
    }

    const authoritySeqs = new Map<string, number[]>();
    const usedResponses = new Set<string>();
    const actionsByAssessment = new Map<string, Array<{
      sequence: number;
      action: string;
      terminality: string;
    }>>();
    for (const row of ambiguity.t5_3Rows) {
      const values = row.values;
      const current = assessments.get(values.ambiguityId)?.at(-1);
      const seq = exactPositive(values.authoritySeq);
      if (!seq) fail(`${values.ambiguityId} authority_seq is invalid`);
      else {
        const bucket = authoritySeqs.get(values.ambiguityId) || [];
        bucket.push(seq); authoritySeqs.set(values.ambiguityId, bucket);
      }
      if (!current || values.assessmentSeq !== current.values.assessmentSeq
        || current.values.resolutionState !== 'unresolved') {
        fail(`${values.ambiguityId} T5.3 row is not bound to the current unresolved assessment`);
      }
      if (!(PROCEDURAL_ACTIONS as readonly string[]).includes(values.action)) fail(`${values.ambiguityId} T5.3 action is invalid`);
      if (values.selectedCandidateRef !== 'none') fail(`${values.ambiguityId} selected_candidate_ref must equal none`);
      if (!/^sha256:[a-f0-9]{64}$/u.test(values.authoritySubjectDigest)) fail(`${values.ambiguityId} authority subject digest is invalid`);
      if (!/^authority-response:RESP-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*@sha256:[a-f0-9]{64}$/u.test(values.authorityRef)) {
        fail(`${values.ambiguityId} authority_ref is invalid`);
      }
      if (!/^request:GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*@sha256:[a-f0-9]{64};response:RESP-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*@sha256:[a-f0-9]{64}$/u.test(values.closureProvenance)) {
        fail(`${values.ambiguityId} closure_provenance is invalid`);
      }
      const responseId = values.authorityRef.match(
        /^authority-response:(RESP-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*)@/u,
      )?.[1];
      const requestId = responseId?.replace(/^RESP/u, 'GATE') || '';
      const request = control.requests.get(requestId);
      const response = control.responses.get(requestId);
      if (!request || !response) {
        fail(`${values.ambiguityId} T5.3 row does not resolve one retained request/response pair`);
      } else {
        try {
          const expected = buildProceduralAuthorityLedgerRow({
            request: request.value,
            request_bytes: request.bytes,
            response: response.value,
            response_bytes: response.bytes,
            authority_seq: seq || 0,
          });
          if (JSON.stringify(expected) !== JSON.stringify(values)) {
            fail(`${values.ambiguityId} T5.3 row is not the exact Core response projection`);
          }
          if (usedResponses.has(response.value.response_id)) {
            fail(`${values.ambiguityId} reuses authority response ${response.value.response_id}`);
          }
          usedResponses.add(response.value.response_id);
          const consequence = request.value.authority_subject.action_consequences.find(
            (entry) => entry.action === response.value.selected_action,
          );
          if (!consequence) {
            fail(`${values.ambiguityId} action has no Core-projected consequence`);
          } else {
            const key = `${values.ambiguityId}\0${values.assessmentSeq}`;
            const history = actionsByAssessment.get(key) || [];
            history.push({
              sequence: seq || 0,
              action: values.action,
              terminality: consequence.terminality,
            });
            actionsByAssessment.set(key, history);
          }
        } catch (error) {
          fail(`${values.ambiguityId} T5.3 retained binding is invalid: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
    }
    for (const [id, sequences] of authoritySeqs) {
      sequences.sort((a, b) => a - b);
      if (sequences.some((value, index) => value !== index + 1)) fail(`${id} authority history is forked or noncontiguous`);
    }
    for (const [key, history] of actionsByAssessment) {
      history.sort((left, right) => left.sequence - right.sequence);
      const terminalIndexes = history
        .map((entry, index) => (
          entry.terminality === 'nonterminal'
            || entry.terminality === 'nonterminal-suspensive'
            ? -1
            : index
        ))
        .filter((index) => index >= 0);
      if (terminalIndexes.length > 1
        || (terminalIndexes.length === 1 && terminalIndexes[0] < history.length - 1)) {
        fail(`${key.replace('\0', ' A')} has a conflicting action after a terminal response`);
      }
      const latest = history.at(-1);
      if (hasC2 && latest
        && latest.action !== 'carry-unresolved'
        && latest.action !== 'restrict-downstream-use') {
        fail(`${key.replace('\0', ' A')} has no progression-enabling terminal response at C2`);
      }
    }
    if (hasC2) {
      for (const [id, rows] of assessments) {
        const latestAssessment = rows.at(-1);
        if (!latestAssessment || latestAssessment.values.resolutionState !== 'unresolved') continue;
        const key = `${id}\0${latestAssessment.values.assessmentSeq}`;
        const material = latestMaterial.get(key);
        if (!material || material.verdict !== 'upheld') continue;
        if (material.subject.materiality_class === 'C') {
          const latestAction = actionsByAssessment.get(key)
            ?.sort((left, right) => left.sequence - right.sequence)
            .at(-1);
          if (!latestAction
            || (latestAction.action !== 'carry-unresolved'
              && latestAction.action !== 'restrict-downstream-use')) {
            fail(`${id} latest upheld Class C material-impact basis lacks a progression-enabling terminal T5.3 action at C2`);
          }
        }
      }
    }
    if (hasC2 && control.active > 0) {
      fail('C2 finalization is illegal while an authority request remains active');
    }
    for (const [requestId, response] of control.responses) {
      if (!control.latestRequestIds.has(requestId)
        && !usedResponses.has(response.value.response_id)) {
        fail(`${response.value.response_id} is a stale response to a replaced request`);
      }
    }
    if (hasC2) {
      for (const response of control.responses.values()) {
        if (!usedResponses.has(response.value.response_id)) {
          fail(`${response.value.response_id} was not applied exactly once to T5.3 before C2`);
        }
      }
    }

    return `${String(definitions.size)} ambiguity definition(s), ${String(ambiguity.t5_2Rows.length)} assessment(s), and ${String(ambiguity.t5_3Rows.length)} procedural row(s) are structurally valid; STRUCTURAL ONLY`;
  });
}
