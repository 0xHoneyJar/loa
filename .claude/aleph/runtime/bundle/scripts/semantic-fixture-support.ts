import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildBundlePlan, bundleLockBytes, createBundleLock, type AdapterManifest, type CoreManifest,
} from './lib/bundle-format.ts';
import { loadRun, EXACT_EVIDENCE_FORMAT } from './lib/run-model.ts';
import {
  materialHash, materialTableMarkdown, prepareRepresentationCapture, readRepresentationContext,
  representationMarkdown, representationUseDigest, representationUsesMarkdown, type MaterialRow, type MaterialUseInput,
} from './lib/source-representation.ts';
import {
  buildSemanticSubject, emptySemanticLedger, semanticAssignmentPath, semanticCoverage,
  semanticJson, semanticLedgerMarkdown, semanticMaterialViews, semanticProducerBinding,
  semanticPromptRequirements, semanticResultPath, semanticSubjectPath, semanticOriginProjection, semanticStageSeal, SEMANTIC_ASSIGNMENT_FORMAT,
  semanticClaimCell,
  SEMANTIC_FACETS, SEMANTIC_PATH, SEMANTIC_RESULT_FORMAT,
  type AnchorInput, type AtomicUnit, type LineageContext, type SemanticAssignment, type SemanticEntry, type SemanticLedger,
  type SemanticResult, type SemanticReviewerProfile, type Semantics, type SemanticSubject,
} from './lib/semantic-review.ts';
import { validateRun } from './validate-run.ts';
import { sourceWalkReviewBasisDigest } from './lib/checks-k2.ts';
import { parseTables } from './lib/markdown.ts';

export const SEMANTIC_TEST_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const MANUAL_REVIEWER: SemanticReviewerProfile = {
  profile_id: 'n/a (core-manual)', profile_digest: null, role: 'verifier-l2s', model_identity: 'human',
};
export const TEXT_USE: MaterialUseInput = {
  requirements: [{ object_id: 'OBJ-0002', feature: 'text-bytes', binding_ids: ['BND-0001'] }],
  use_state: 'usable', fidelity_claim: 'none', limitation_refs: [], reason: 'none',
};
export function writeFixtureFile(run: string, path: string, bytes: string | Buffer): void {
  mkdirSync(dirname(join(run, path)), { recursive: true });
  writeFileSync(join(run, path), bytes);
}
export function fixtureTable(headers: string[], cells: string[][]): string {
  return materialTableMarkdown(headers, cells.map((row) => Object.fromEntries(headers.map((h, i) => [h, row[i]]))));
}
export function fixtureUnit(proposition: string, exactText: string, id = 'U1', anchor = 'A1'): AtomicUnit {
  const facets = Object.fromEntries(Object.keys(SEMANTIC_FACETS).map((name) => [name,
    { state: 'not-expressed', items: [], basis_anchor_ids: [anchor] }]));
  facets.claim_roles = { state: 'present', items: [{ kind: 'result-observation', source_text: exactText, anchor_ids: [anchor] }], basis_anchor_ids: [anchor] } as never;
  return { unit_id: id, proposition, proposition_anchor_ids: [anchor], ...facets } as AtomicUnit;
}
export function fixtureSemantics(text: string): Semantics {
  return { atomicity: 'single-assertion', units: [fixtureUnit(text.trim(), text)],
    contexts: [], couplings: [], relation_proposals: [], unresolved_findings: [] };
}
export function fixtureResult(subject: SemanticSubject): SemanticResult {
  return { format: SEMANTIC_RESULT_FORMAT, subject_digest: materialHash(semanticJson(subject)), verdict: 'upheld',
    field_reviews: semanticCoverage(subject.semantics, subject.subject_kind).map((field_path) => ({
      field_path, verdict: 'upheld', issue: 'none', anchor_ids: subject.anchors.length ? ['A1'] : [],
      material_requirement_indexes: subject.anchors.length ? [] : [0],
      explanation: 'Synthetic declared counter-reading considered; this fixture does not establish semantic correctness.',
    })), unresolved_findings: [], attacks_tried: ['Synthetic stronger and weaker reading challenge.'],
    missing_for_determination: null, rationale: 'This static declaration exercises structural accounting only.', candidate_evidence: [] };
}
export function fixtureCompanion(subject: SemanticSubject, result: SemanticResult): string {
  return `# Semantic review companion\n\n${fixtureTable(['field', 'value'], [
    ['target', `semantic-review-subject:${result.subject_digest}`], ['lens', 'L2S'], ['stage', subject.owner_stage],
    ['shown', semanticSubjectPath(subject.semantic_id)], ['withheld', 'Producer identity, rationale, previous reviews and authority records.'],
    ['verdict', result.verdict], ['consequence', 'Synthetic structural evidence only; no semantic certification.'],
  ])}`;
}
export interface SemanticFixture {
  run: string; source: Buffer; subject: SemanticSubject; entry: SemanticEntry; returned: Record<string, unknown>;
  producer: { call_id: string; context_id: string; raw_return_hash: string; output_kind: string; output_index: number };
  assignment: SemanticAssignment; result: SemanticResult; ledger: SemanticLedger;
}
export function makeSemanticFixture(run: string, text = 'With the filter enabled, the counter rose.',
  declaredSemantics?: Semantics, anchors?: AnchorInput[]): SemanticFixture {
  const root = SEMANTIC_TEST_ROOT;
  const manifest = JSON.parse(readFileSync(join(root, 'core.manifest.json'), 'utf8')) as CoreManifest;
  const adapter = JSON.parse(readFileSync(join(root, 'adapters/loa/adapter.manifest.json'), 'utf8')) as AdapterManifest;
  const lock = createBundleLock(buildBundlePlan(root, manifest, manifest.bundle_targets.find((t) => t.adapter_id === 'loa')!, adapter));
  writeFixtureFile(run, 'control/runtime/bundle/bundle.lock.json', bundleLockBytes(lock));
  for (const path of new Set(['S2', 'S3', 'S4'].flatMap((stage) => semanticPromptRequirements(stage as 'S2').map((p) => p.path)))) {
    writeFixtureFile(run, `control/runtime/bundle/${path}`, readFileSync(join(root, path)));
  }
  writeFixtureFile(run, 'README.md', '# Semantic structural fixture\n\n```aleph-fixture\nkind: run\nsrc_ids: SRC-701\n```\n\nSynthetic source and declared manual process records only. No human/model review was executed.\n');
  const source = Buffer.from(text);
  const fragment = text.endsWith('\n') ? source.subarray(0, -1) : source;
  const semantics = declaredSemantics || fixtureSemantics(fragment.toString('utf8'));
  writeFixtureFile(run, 'corpus/sources/semantic.txt', source);
  const capture = prepareRepresentationCapture([{ source_id: 'SRC-701', bytes: source }]);
  const inventory = representationMarkdown(capture.inventory);
  writeFixtureFile(run, 'corpus/representations.md', inventory);
  const corpus = '# Corpus Manifest\n\n' + fixtureTable(['source_id', 'kind', 'locus', 'scheme', 'content_hash', 'date(s)', 'trust_class', 'sensitivity', 'admission note'],
    [['SRC-701', 'design-note', 'sources/semantic.txt', 'md-lines', materialHash(source), '2026-09-12', 'model-generated', 'none', 'Synthetic semantic contract exercise']]);
  writeFixtureFile(run, 'corpus/manifest.md', corpus);
  let runManifest = readFileSync(join(root, 'docs/fixtures/exact-evidence-fragments/run-manifest.md'), 'utf8')
    .replaceAll('RUN-exact-evidence-fragments', 'RUN-semantic-unit-review')
    .replace('1.1.0-provisional', '1.7.0-provisional');
  for (const [key, value] of Object.entries({ core_digest: lock.core.tree_digest, checker_digest: lock.checker_digest,
    bundle_digest: lock.bundle.digest, bundle_lock_ref: 'control/runtime/bundle/bundle.lock.json', corpus_hash: materialHash(source) })) {
    runManifest = runManifest.replace(new RegExp(`^-${' '}${key}: .+$`, 'mu'), `- ${key}: ${value}`);
  }
  runManifest = runManifest.replace('## Corpus binding', `## Corpus binding\n\n- representation_inventory_hash: ${materialHash(inventory)}`);
  writeFixtureFile(run, 'run-manifest.md', runManifest);
  writeFixtureFile(run, 'run-log.md', '# Run Log\n\n## 2026-09-12 08:00 UTC — S0 — entry\n\nSynthetic setup.\n\n## 2026-09-12 08:05 UTC — S0 — exit\n\nFixture-simulated scope freeze.\n\n## 2026-09-12 08:10 UTC — S1 — exit\n\nCriteria frozen.\n\n## 2026-09-12 08:20 UTC — S2 — entry\n\nSynthetic manual semantic review records.\n');
  const locator = `L1-L${text.split('\n').length - (text.endsWith('\n') ? 1 : 0)}`;
  const size = Buffer.alloc(8); size.writeBigUInt64BE(BigInt(fragment.length));
  const evidenceHash = materialHash(Buffer.concat([Buffer.from(`${EXACT_EVIDENCE_FORMAT}\0`), size, fragment]));
  writeFixtureFile(run, 'ledgers/packet-index.md', `# Packet Index\n\n- exact_evidence_format: ${EXACT_EVIDENCE_FORMAT}\n\n## Packets\n\n`
    + fixtureTable(['packet_id', 'source_id', 'locator', 'span_hash', 'quote', 'criterion', 'status'],
      [['PKT-0701', 'SRC-701', locator, materialHash(fragment), text.trim(), '1', 'active']])
    + '\n## Exact evidence records\n\n' + fixtureTable(['evidence_key', 'packet_ids', 'evidence_state', 'fragment_count', 'join_policy', 'exact_evidence_hash', 'degraded_source_id', 'degraded_source_locator', 'degradation_reason'],
      [['EVID-0701', 'PKT-0701', 'exact', '1', 'single-fragment', evidenceHash, 'none', 'none', 'none']])
    + '\n## Exact fragments\n\n' + fixtureTable(['fragment_key', 'evidence_key', 'packet_id', 'fragment_order', 'source_id', 'locator', 'source_relation', 'byte_role', 'fragment_hash', 'exact_bytes_base64'],
      [['FRAG-0701', 'EVID-0701', 'PKT-0701', '1', 'SRC-701', locator, 'frozen-source', 'exact-source-bytes', materialHash(fragment), fragment.toString('base64')]])
    + '\n## Evidence transformations\n\n' + fixtureTable(['transform_key', 'evidence_key', 'output_role', 'predecessor_exact_evidence_hash', 'effective_exact_evidence_hash', 'output_text', 'output_text_hash'], []));
  writeFixtureFile(run, 'ledgers/claim-inventory.md', '# Candidate-Claim Inventory\n\n' + fixtureTable(['claim_id', 'normalized claim', 'packets', 'sources', 'claim_type', 'disposition', 'rationale', 'judged_by', 'verified', 'status'], []));
  writeFixtureFile(run, 'ledgers/disposition-ledger.md', '# Disposition Ledger\n');
  writeFixtureFile(run, 'ledgers/lineage.md', '# Unit Lineage\n\n- lineage_format: aleph-lineage/v1\n\n'
    + fixtureTable(['lineage_id', 'owner_stage', 'type', 'predecessors', 'successors', 'basis', 'established_by'], []));
  writeFixtureFile(run, 'ledgers/extraction-criteria.md', '# Extraction Criteria\n\n- written: 2026-09-12 08:10 UTC\n\n## Admission criteria\n\n'
    + fixtureTable(['#', 'criterion', 'example span that qualifies'], [['1', 'Explicit observations in the frozen synthetic source.', 'A direct assertion.']])
    + '\n## Exclusion classes\n\n' + fixtureTable(['class', 'description', 'example'], [['scaffolding', 'Headings without assertions.', 'A heading.']]));
  const walkPrefix = '# Source Walk Ledger\n\n- source_walk_format: aleph-source-walk/v1\n- source_position_format: zero-based-utf8-byte-half-open/v1\n\n## Primary walk intervals\n\n'
    + fixtureTable(['walk_id', 'source_id', 'start_byte', 'end_byte', 'outcome', 'packet_ids', 'criterion_ref', 'producer_invocation_id', 'closure_state', 'reason', 'closure_note'],
      [['WLK-0701', 'SRC-701', '0', String(source.length), 'admitted', 'PKT-0701', 'admission:1', 'manual-producer-0701', 'closed', 'none', 'none']])
    + '\n## Extraction events\n\n' + fixtureTable(['event_id', 'source_id', 'start_byte', 'end_byte', 'shared_position_key', 'event_ordinal', 'packet_id', 'origin', 'producer_invocation_id', 'status'],
      [['EVT-0701', 'SRC-701', '0', String(fragment.length), 'SP-0701', '1', 'PKT-0701', 'primary', 'manual-producer-0701', 'committed']])
    + '\n## Resume cursors\n\n' + fixtureTable(['cursor_id', 'source_id', 'byte_offset', 'shared_position_key', 'next_event_ordinal', 'predecessor_walk_id', 'predecessor_event_id', 'source_hash', 'reason'],
      [['CUR-0701', 'SRC-701', '0', 'none', 'none', 'none', 'none', materialHash(source), 'initial'],
        ['CUR-0702', 'SRC-701', String(source.length), 'none', 'none', 'WLK-0701', 'EVT-0701', materialHash(source), 'source-complete']]);
  const gapHeaders = ['gap_review_id', 'source_id', 'producer_invocation_id', 'reviewer_invocation_id', 'review_basis_cursor_id', 'review_basis_digest', 'result', 'candidate_start_byte', 'candidate_end_byte', 'proposed_packet_id', 'reconciliation_event_id', 'status', 'note'];
  const completion = '\n## Per-source completion\n\n' + fixtureTable(['source_id', 'source_hash', 'source_length_bytes', 'final_cursor_id', 'gap_review_ids', 'completion_state', 'declared_by', 'note'],
    [['SRC-701', materialHash(source), String(source.length), 'CUR-0702', 'GAP-0701', 'complete', 'synthetic-manual-coordinator', 'Synthetic gap record; no actual review execution.']]);
  writeFixtureFile(run, 'ledgers/source-walk.md', walkPrefix + '\n## Fresh gap reviews\n\n' + fixtureTable(gapHeaders, []) + completion);
  const walkDigest = sourceWalkReviewBasisDigest(loadRun(run), 'SRC-701', 'CUR-0702');
  assert(walkDigest);
  writeFixtureFile(run, 'ledgers/source-walk.md', walkPrefix + '\n## Fresh gap reviews\n\n' + fixtureTable(gapHeaders,
    [['GAP-0701', 'SRC-701', 'manual-producer-0701', 'manual-gap-0701', 'CUR-0702', walkDigest, 'no-gap-candidate-found', 'none', 'none', 'none', 'none', 'closed', 'Synthetic independent gap-review declaration.']]) + completion);
  const useRow: MaterialRow = { use_id: 'USE-0701', owner_stage: 'S2', subject_kind: 'PKT', subject_id: 'PKT-0701',
    basis_packet_ids: '["PKT-0701"]', requirements: semanticJson(TEXT_USE.requirements), use_state: 'usable', fidelity_claim: 'none',
    limitation_refs: '[]', reason: 'none', established_by: 'synthetic-manual-producer', review_subject_digest: '', reviewed_by: 'none' };
  let model = loadRun(run);
  useRow.review_subject_digest = representationUseDigest(model, readRepresentationContext(model), useRow);
  writeFixtureFile(run, 'ledgers/representation-uses.md', representationUsesMarkdown([useRow]));
  const entry: SemanticEntry = { output_kind: 'packet-candidate', output_index: 0, review_mode: 'proposal', origin_unit_refs: [],
    anchors: anchors || [{ anchor_id: 'A1', source_id: 'SRC-701', locator, start_byte: 0, end_byte: fragment.length, exact_bytes_base64: fragment.toString('base64') }], semantics };
  const returned = { source_id: 'SRC-701', producer_invocation_id: 'manual-producer-0701',
    walk_intervals: [{ start_byte: 0, end_byte: source.length, outcome: 'admitted', packet_candidate_indexes: [0], criterion_ref: 'admission:1', closure_state: 'closed', reason: null, closure_note: null }],
    packets: [{ evidence_state: 'exact', join_policy: 'single-fragment', fragments: [{ fragment_order: 1, locator, exact_bytes_base64: fragment.toString('base64') }],
      rendered_text: text.trim(), degraded_source_locator: null, degradation_reason: null, criterion: 1, flags: [], material_use: TEXT_USE }],
    extraction_events: [{ start_byte: 0, end_byte: fragment.length, shared_position_key: 'SP-0701', event_ordinal: 1, packet_candidate_index: 0, origin: 'primary' }],
    next_cursor: { byte_offset: source.length, shared_position_key: null, next_event_ordinal: null, predecessor_walk_index: 0, predecessor_event_index: 0, source_hash: materialHash(source), reason: 'source-complete' },
    walk_exhausted: true, notes: [], material_findings: [], semantic_units: [entry] };
  const producer = { call_id: 'manual-producer-0701', context_id: 'manual-producer-pass-0701', raw_return_hash: materialHash(semanticJson(returned)), output_kind: 'packet-candidate', output_index: 0 };
  const producerPath = 'verification/harness/semantic-process/producer-0701.json';
  writeFixtureFile(run, producerPath, semanticJson(producer));
  writeFixtureFile(run, `verification/harness/semantic-process/${producer.call_id}.raw.json`, semanticJson(returned));
  model = loadRun(run);
  const subject = buildSemanticSubject(model, { semantic_id: 'SEM-0701', owner_stage: 'S2', subject_kind: 'packet-group', review_mode: 'proposal',
    predecessor_semantic_id: 'none', producer_binding_hash: semanticProducerBinding(producer), reviewer_profile: MANUAL_REVIEWER,
    output_binding: { kind: 'packet-group', evidence_keys: ['EVID-0701'], packet_ids: ['PKT-0701'] },
    origin_unit_refs: [], origin_context: [], anchors: entry.anchors, semantics, material_use: TEXT_USE,
    material_views: semanticMaterialViews(model, [useRow]), lineage_context: [], relation_context: [], ambiguity_context: [] });
  const digest = materialHash(semanticJson(subject)), result = fixtureResult(subject);
  const assignment: SemanticAssignment = { format: SEMANTIC_ASSIGNMENT_FORMAT, semantic_id: subject.semantic_id, subject_digest: digest,
    review_id: 'VER-0701', role: 'verifier-l2s', profile_digest: null, invocation_id: 'manual-reviewer-pass-0701',
    producer_binding_hash: subject.producer_binding_hash, execution_kind: 'manual-separate-pass' };
  const evidencePath = 'verification/harness/semantic-process/reviewer-0701.json';
  const evidence = semanticJson({ producer_actor: 'synthetic-person-a', reviewer_actor: 'synthetic-person-b',
    producer_pass_id: producer.context_id, reviewer_pass_id: assignment.invocation_id, subject_digest: digest, shown_digest: digest,
    withheld_declaration: 'Only the sealed subject and declared material were shown; no producer history, other verdicts or authority records.' });
  writeFixtureFile(run, evidencePath, evidence);
  writeFixtureFile(run, semanticSubjectPath(subject.semantic_id), semanticJson(subject));
  writeFixtureFile(run, semanticAssignmentPath(assignment.review_id), semanticJson(assignment));
  writeFixtureFile(run, semanticResultPath(assignment.review_id), semanticJson(result));
  writeFixtureFile(run, 'verification/harness/S2/VER-0701.md', fixtureCompanion(subject, result));
  const ledger = emptySemanticLedger();
  ledger.subjects.push({ semantic_id: subject.semantic_id, owner_stage: 'S2', subject_kind: subject.subject_kind,
    subject_path: semanticSubjectPath(subject.semantic_id), subject_digest: digest, predecessor_semantic_id: 'none',
    producer_receipt_ref: `${producerPath}@${materialHash(semanticJson(producer))}` });
  ledger.assignments.push({ review_id: assignment.review_id, semantic_id: subject.semantic_id, assignment_path: semanticAssignmentPath(assignment.review_id), assignment_digest: materialHash(semanticJson(assignment)) });
  ledger.results.push({ review_id: assignment.review_id, semantic_id: subject.semantic_id, result_path: semanticResultPath(assignment.review_id),
    result_digest: materialHash(semanticJson(result)), execution_kind: assignment.execution_kind, execution_evidence_ref: `${evidencePath}@${materialHash(evidence)}` });
  ledger.resolutions.push({ resolution_id: 'SMR-0701', semantic_id: subject.semantic_id, outcome: 'admitted', review_ids: '["VER-0701"]',
    canonical_refs: '["PKT-0701"]', origin_unit_refs: '[]', followup_semantic_ids: '[]' });
  writeFixtureFile(run, SEMANTIC_PATH, semanticLedgerMarkdown(ledger));
  return { run, source, subject, entry, returned, producer, assignment, result, ledger };
}
export function assertSemanticFixture(run: string): void {
  const report = validateRun({ root: SEMANTIC_TEST_ROOT, run });
  assert.equal(report.result, 'PASS', JSON.stringify(report.checks.filter((c) => c.status === 'FAIL'), null, 2));
  assert(report.checks.some((c) => c.id === 'K2.19' && c.status === 'PASS'));
}

/** Synthetic ordered fragments; no production extraction or source-walk proof. */
export function makeFragmentSemanticFixture(run: string): SemanticFixture {
  const first = 'The counter rose.', middle = 'Unrelated surrounding text.', last = 'The battery discharged.';
  const text = `${first}\n${middle}\n${last}`, start = Buffer.byteLength(`${first}\n${middle}\n`);
  const anchors: AnchorInput[] = [
    { anchor_id: 'A1', source_id: 'SRC-701', locator: 'L1-L1', start_byte: 0, end_byte: Buffer.byteLength(first), exact_bytes_base64: Buffer.from(first).toString('base64') },
    { anchor_id: 'A2', source_id: 'SRC-701', locator: 'L3-L3', start_byte: start, end_byte: Buffer.byteLength(text), exact_bytes_base64: Buffer.from(last).toString('base64') },
  ];
  const semantics: Semantics = { atomicity: 'multiple-separable', units: [fixtureUnit(first, first), fixtureUnit(last, last, 'U2', 'A2')],
    contexts: [], couplings: [], relation_proposals: [], unresolved_findings: [] };
  const f = makeSemanticFixture(run, text, semantics, anchors);
  const packetText = readFileSync(join(run, 'ledgers/packet-index.md'), 'utf8'), tables = parseTables(packetText);
  const exactFragments = [Buffer.from(`${first}\n`), Buffer.from(last)];
  const packetRows = anchors.map((a, i) => [`PKT-070${i + 1}`, 'SRC-701', a.locator, materialHash(exactFragments[i]),
    i === 0 ? first : last, '1', 'active']);
  const fragments = anchors.map((a, i) => [`FRAG-070${i + 1}`, 'EVID-0701', `PKT-070${i + 1}`, String(i + 1), 'SRC-701',
    a.locator, 'frozen-source', 'exact-source-bytes', materialHash(exactFragments[i]), exactFragments[i].toString('base64')]);
  const framed = exactFragments.flatMap((b) => { const size = Buffer.alloc(8); size.writeBigUInt64BE(BigInt(b.length)); return [size, b]; });
  writeFixtureFile(run, 'ledgers/packet-index.md', `# Packet Index\n\n- exact_evidence_format: ${EXACT_EVIDENCE_FORMAT}\n\n## Packets\n\n`
    + fixtureTable(tables[0].header, packetRows) + '\n## Exact evidence records\n\n'
    + fixtureTable(tables[1].header, [['EVID-0701', 'PKT-0701, PKT-0702', 'exact', '2', 'separate-fragments',
      materialHash(Buffer.concat([Buffer.from(`${EXACT_EVIDENCE_FORMAT}\0`), ...framed])), 'none', 'none', 'none']])
    + '\n## Exact fragments\n\n' + fixtureTable(tables[2].header, fragments)
    + '\n## Evidence transformations\n\n' + fixtureTable(tables[3].header, []));
  let walk = readFileSync(join(run, 'ledgers/source-walk.md'), 'utf8')
    .replace('| admitted | PKT-0701 |', '| admitted | PKT-0701, PKT-0702 |')
    .replace(`| EVT-0701 | SRC-701 | 0 | ${Buffer.byteLength(text)} |`, `| EVT-0701 | SRC-701 | 0 | ${exactFragments[0].length} |`)
    .replace('\n\n## Resume cursors', `\n| EVT-0702 | SRC-701 | ${start} | ${Buffer.byteLength(text)} | SP-0702 | 1 | PKT-0702 | primary | manual-producer-0701 | committed |\n\n## Resume cursors`)
    .replace('| WLK-0701 | EVT-0701 |', '| WLK-0701 | EVT-0702 |');
  writeFixtureFile(run, 'ledgers/source-walk.md', walk);
  const oldGap = parseTables(walk).find((t) => t.header[0] === 'gap_review_id')!.rows[0].cells[5];
  walk = walk.replace(oldGap, sourceWalkReviewBasisDigest(loadRun(run), 'SRC-701', 'CUR-0702')!);
  writeFixtureFile(run, 'ledgers/source-walk.md', walk);
  const model = loadRun(run), material = readRepresentationContext(model), template = material.uses[0];
  const uses = packetRows.map((row, i) => {
    const use: MaterialRow = { ...template, use_id: `USE-070${i + 1}`, subject_id: row[0], basis_packet_ids: semanticJson([row[0]]) };
    use.review_subject_digest = representationUseDigest(model, material, use); return use;
  });
  writeFixtureFile(run, 'ledgers/representation-uses.md', representationUsesMarkdown(uses));
  const packets = f.returned.packets as Array<Record<string, unknown>>;
  packets[0].join_policy = 'separate-fragments';
  packets[0].fragments = anchors.map((a, i) => ({ fragment_order: i + 1, locator: a.locator, exact_bytes_base64: exactFragments[i].toString('base64') }));
  packets[0].rendered_text = `${first} ${last}`;
  f.returned.extraction_events = anchors.map((a, i) => ({ start_byte: a.start_byte, end_byte: a.start_byte + exactFragments[i].length, shared_position_key: `SP-070${i + 1}`,
    event_ordinal: 1, packet_candidate_index: 0, origin: 'primary' }));
  (f.returned.next_cursor as Record<string, unknown>).predecessor_event_index = 1;
  f.producer.raw_return_hash = materialHash(semanticJson(f.returned));
  const receiptPath = f.ledger.subjects[0].producer_receipt_ref.split('@')[0];
  writeFixtureFile(run, receiptPath, semanticJson(f.producer));
  writeFixtureFile(run, `verification/harness/semantic-process/${f.producer.call_id}.raw.json`, semanticJson(f.returned));
  f.subject = buildSemanticSubject(loadRun(run), { semantic_id: 'SEM-0701', owner_stage: 'S2', subject_kind: 'packet-group', review_mode: 'proposal',
    predecessor_semantic_id: 'none', producer_binding_hash: semanticProducerBinding(f.producer), reviewer_profile: MANUAL_REVIEWER,
    output_binding: { kind: 'packet-group', evidence_keys: ['EVID-0701'], packet_ids: ['PKT-0701', 'PKT-0702'] }, origin_unit_refs: [], origin_context: [],
    anchors, semantics, material_use: TEXT_USE, material_views: semanticMaterialViews(loadRun(run), uses), lineage_context: [], relation_context: [], ambiguity_context: [] });
  const digest = materialHash(semanticJson(f.subject));
  writeFixtureFile(run, semanticSubjectPath('SEM-0701'), semanticJson(f.subject));
  Object.assign(f.ledger.subjects[0], { subject_digest: digest, producer_receipt_ref: `${receiptPath}@${materialHash(semanticJson(f.producer))}` });
  f.ledger.resolutions[0].canonical_refs = '["PKT-0701","PKT-0702"]';
  f.assignment.subject_digest = digest; f.assignment.producer_binding_hash = f.subject.producer_binding_hash;
  f.result = fixtureResult(f.subject); fixtureReview(f, f.result);
  return f;
}

export function sealFixtureSemanticStage(f: SemanticFixture, stage: 'S2' | 'S3'): void {
  const path = `verification/harness/semantic-stage-seals/${stage}.json`, bytes = semanticJson(semanticStageSeal(f.ledger, stage));
  writeFixtureFile(f.run, path, bytes);
  writeFixtureFile(f.run, 'run-log.md', readFileSync(join(f.run, 'run-log.md'), 'utf8')
    + `\n## 2026-09-12 0${stage === 'S2' ? '8' : '9'}:30 UTC — ${stage} — exit\n\nsemantic_stage: ${stage}\nsemantic_review_seal_ref: ${path}@${materialHash(bytes)}\n`);
}

/** Test declarations only: this does not exercise the production single writer. */
export function addFixtureNormalization(f: SemanticFixture, options: {
  noClaim?: boolean; semantics?: Semantics; proposition?: string; number?: string;
  predecessor?: string; origins?: string[]; outcome?: 'admitted' | 'not-admitted' | 'unresolved-recorded';
  lineage?: LineageContext;
} = {}): SemanticFixture {
  const stage = options.lineage ? 'S4' : 'S3';
  const number = options.number || '0702', id = `SEM-${number}`, packet = f.subject.output_binding.kind === 'packet-group'
    ? f.subject.output_binding.packet_ids[0] : 'PKT-0701';
  if (!readFileSync(join(f.run, 'run-log.md'), 'utf8').includes('semantic_stage: S2')) {
    sealFixtureSemanticStage(f, 'S2');
    writeFixtureFile(f.run, 'run-log.md', readFileSync(join(f.run, 'run-log.md'), 'utf8') + '\n## 2026-09-12 09:00 UTC — S3 — entry\n\nSynthetic normalization records.\n');
  }
  if (stage === 'S4' && !readFileSync(join(f.run, 'run-log.md'), 'utf8').includes('semantic_stage: S3')) {
    sealFixtureSemanticStage(f, 'S3');
    writeFixtureFile(f.run, 'run-log.md', readFileSync(join(f.run, 'run-log.md'), 'utf8') + '\n## 2026-09-12 10:00 UTC — S4 — entry\n\nSynthetic already-proposed successor.\n');
  }
  const origins = options.origins || f.subject.semantics.units.map((unit) => `${f.subject.semantic_id}/${unit.unit_id}`);
  const semantics = options.semantics || (options.noClaim
    ? { atomicity: 'no-claim', units: [], contexts: [], couplings: [], relation_proposals: [], unresolved_findings: [] } as Semantics
    : fixtureSemantics(Buffer.from(f.entry.anchors[0].exact_bytes_base64, 'base64').toString('utf8')));
  if (options.proposition && semantics.units[0]) semantics.units[0].proposition = options.proposition;
  const entry: SemanticEntry = { output_kind: options.noClaim ? 'no-claim-candidate' : 'claim-candidate', output_index: 0,
    review_mode: options.outcome === 'unresolved-recorded' ? 'unresolved-record' : 'proposal',
    origin_unit_refs: origins, anchors: f.entry.anchors, semantics };
  const claim = { normalized_claim: semantics.units[0]?.proposition || 'Tentative unresolved proposal.', packets: [packet],
    claim_type: 'factual', widen_requests: [], rationale: 'Synthetic proposed normalization for structural testing.', flags: [], material_use: TEXT_USE };
  const returned = { claims: options.noClaim ? [] : [claim], no_claim_packets: options.noClaim ? [{ packet, basis: 'Synthetic explicit no-claim proposal.' }] : [],
    lineage_proposals: [], material_findings: [], semantic_units: [entry] };
  const producer = { call_id: `manual-producer-${number}`, context_id: `manual-producer-pass-${number}`,
    raw_return_hash: materialHash(semanticJson(returned)), output_kind: entry.output_kind, output_index: 0 };
  const producerPath = `verification/harness/semantic-process/producer-${number}.json`;
  writeFixtureFile(f.run, producerPath, semanticJson(producer));
  writeFixtureFile(f.run, `verification/harness/semantic-process/${producer.call_id}.raw.json`, semanticJson(returned));
  const model = loadRun(f.run), context = readRepresentationContext(model);
  const useRow: MaterialRow = { use_id: `USE-${number}`, owner_stage: stage, subject_kind: 'CC', subject_id: `CC-${number}`,
    basis_packet_ids: semanticJson([packet]), requirements: semanticJson(TEXT_USE.requirements), use_state: 'usable', fidelity_claim: 'none',
    limitation_refs: '[]', reason: 'none', established_by: 'synthetic-manual-normalizer', review_subject_digest: '', reviewed_by: 'none' };
  if (!options.noClaim) {
    model.claims.push({ file: 'ledgers/claim-inventory.md', line: 0, raw: '', cells: [], values: {
      claimId: `CC-${number}`, normalizedClaim: semanticClaimCell(claim.normalized_claim), packets: packet, sources: 'SRC-701', claimType: 'factual',
      disposition: '', rationale: '', judgedBy: '', verified: '', status: 'active',
    } });
    useRow.review_subject_digest = representationUseDigest(model, context, useRow);
  }
  const originContext = [...new Set(origins.map((ref) => ref.split('/')[0]))].map((id) =>
    semanticOriginProjection(JSON.parse(readFileSync(join(f.run, semanticSubjectPath(id)), 'utf8')) as SemanticSubject));
  const subject = buildSemanticSubject(model, { semantic_id: id, owner_stage: stage, subject_kind: options.noClaim ? 'no-claim' : 'claim',
    review_mode: entry.review_mode, predecessor_semantic_id: options.predecessor || 'none', producer_binding_hash: semanticProducerBinding(producer),
    reviewer_profile: MANUAL_REVIEWER, output_binding: options.noClaim ? { kind: 'no-claim', packet_id: packet, basis: returned.no_claim_packets[0].basis }
      : { kind: 'claim', reserved_claim_id: `CC-${number}`, normalized_claim: claim.normalized_claim, packet_ids: [packet], source_ids: ['SRC-701'], claim_type: 'factual' },
    origin_unit_refs: origins, origin_context: originContext,
    anchors: entry.anchors, semantics, material_use: options.noClaim ? null : TEXT_USE,
    material_views: semanticMaterialViews(model, options.noClaim ? context.uses.filter((r) => r.subject_kind === 'PKT' && r.subject_id === packet) : [useRow]),
    lineage_context: options.lineage ? [options.lineage] : [], relation_context: [], ambiguity_context: [] });
  const digest = materialHash(semanticJson(subject)), result = fixtureResult(subject);
  const assignment: SemanticAssignment = { format: SEMANTIC_ASSIGNMENT_FORMAT, semantic_id: id, subject_digest: digest,
    review_id: `VER-${number}`, role: 'verifier-l2s', profile_digest: null, invocation_id: `manual-reviewer-pass-${number}`,
    producer_binding_hash: subject.producer_binding_hash, execution_kind: 'manual-separate-pass' };
  const evidencePath = `verification/harness/semantic-process/reviewer-${number}.json`;
  const evidence = semanticJson({ producer_actor: 'synthetic-person-a', reviewer_actor: 'synthetic-person-b',
    producer_pass_id: producer.context_id, reviewer_pass_id: assignment.invocation_id, subject_digest: digest, shown_digest: digest,
    withheld_declaration: 'Only the sealed subject and declared material; no hidden producer/reviewer/authority context.' });
  writeFixtureFile(f.run, evidencePath, evidence);
  writeFixtureFile(f.run, semanticSubjectPath(id), semanticJson(subject));
  writeFixtureFile(f.run, semanticAssignmentPath(assignment.review_id), semanticJson(assignment));
  writeFixtureFile(f.run, semanticResultPath(assignment.review_id), semanticJson(result));
  writeFixtureFile(f.run, `verification/harness/${stage}/${assignment.review_id}.md`, fixtureCompanion(subject, result));
  f.ledger.subjects.push({ semantic_id: id, owner_stage: stage, subject_kind: subject.subject_kind, subject_path: semanticSubjectPath(id),
    subject_digest: digest, predecessor_semantic_id: subject.predecessor_semantic_id, producer_receipt_ref: `${producerPath}@${materialHash(semanticJson(producer))}` });
  f.ledger.assignments.push({ review_id: assignment.review_id, semantic_id: id, assignment_path: semanticAssignmentPath(assignment.review_id), assignment_digest: materialHash(semanticJson(assignment)) });
  f.ledger.results.push({ review_id: assignment.review_id, semantic_id: id, result_path: semanticResultPath(assignment.review_id),
    result_digest: materialHash(semanticJson(result)), execution_kind: assignment.execution_kind, execution_evidence_ref: `${evidencePath}@${materialHash(evidence)}` });
  const outcome = options.noClaim ? 'no-claim' : options.outcome || 'admitted';
  f.ledger.resolutions.push({ resolution_id: `SMR-${number}`, semantic_id: id, outcome, review_ids: semanticJson([assignment.review_id]),
    canonical_refs: semanticJson(options.noClaim ? [packet, `LIN-${number}`] : outcome === 'admitted' ? [`CC-${number}`] : []),
    origin_unit_refs: semanticJson(origins), followup_semantic_ids: '[]' });
  if (options.noClaim) {
    writeFixtureFile(f.run, 'ledgers/lineage.md', readFileSync(join(f.run, 'ledgers/lineage.md'), 'utf8')
      + `| LIN-${number} | S3 | no-claim | ${packet} | none | Synthetic reviewed no-claim. | manual-fixture |\n`);
  } else if (outcome === 'admitted') {
    const path = 'ledgers/claim-inventory.md';
    writeFixtureFile(f.run, path, readFileSync(join(f.run, path), 'utf8')
      + fixtureTable(['claim_id', 'normalized claim', 'packets', 'sources', 'claim_type', 'disposition', 'rationale', 'judged_by', 'verified', 'status'],
        [[`CC-${number}`, claim.normalized_claim, packet, 'SRC-701', 'factual', '', '', '', '', 'active']]).split('\n').slice(2).join('\n'));
    writeFixtureFile(f.run, 'ledgers/representation-uses.md', representationUsesMarkdown([...context.uses, useRow]));
    if (options.lineage) {
      const row = JSON.parse(readFileSync(join(f.run, `verification/harness/semantic-process/${options.lineage.lineage_id}.json`), 'utf8'));
      writeFixtureFile(f.run, 'ledgers/lineage.md', readFileSync(join(f.run, 'ledgers/lineage.md'), 'utf8')
        + `| ${Object.values(row).join(' | ')} |\n`);
    }
  }
  writeFixtureFile(f.run, SEMANTIC_PATH, semanticLedgerMarkdown(f.ledger));
  return { run: f.run, source: f.source, subject, entry, returned, producer, assignment, result, ledger: f.ledger };
}

/** Constructs static initial fixture evidence; never used by a live writer. */
export function fixtureReview(f: SemanticFixture, result: SemanticResult, reviewId = f.assignment.review_id): void {
  const assignment = { ...f.assignment, review_id: reviewId, invocation_id: `manual-pass-${reviewId}` };
  const assignmentRow = { review_id: reviewId, semantic_id: f.subject.semantic_id, assignment_path: semanticAssignmentPath(reviewId),
    assignment_digest: materialHash(semanticJson(assignment)) };
  const evidencePath = `verification/harness/semantic-process/reviewer-${reviewId}.json`;
  const evidence = semanticJson({ producer_actor: 'synthetic-person-a', reviewer_actor: `synthetic-person-${reviewId}`,
    producer_pass_id: f.producer.context_id, reviewer_pass_id: assignment.invocation_id, subject_digest: result.subject_digest,
    shown_digest: result.subject_digest, withheld_declaration: 'Synthetic distinct actor/pass declaration; only sealed subject context shown.' });
  const resultRow = { review_id: reviewId, semantic_id: f.subject.semantic_id, result_path: semanticResultPath(reviewId),
    result_digest: materialHash(semanticJson(result)), execution_kind: 'manual-separate-pass', execution_evidence_ref: `${evidencePath}@${materialHash(evidence)}` };
  const replace = (rows: MaterialRow[], row: MaterialRow): void => {
    const index = rows.findIndex((r) => r.review_id === row.review_id);
    if (index < 0) rows.push(row); else rows[index] = row;
  };
  replace(f.ledger.assignments, assignmentRow); replace(f.ledger.results, resultRow);
  const resolution = f.ledger.resolutions.find((r) => r.semantic_id === f.subject.semantic_id);
  if (resolution) resolution.review_ids = semanticJson(f.ledger.assignments.filter((r) => r.semantic_id === f.subject.semantic_id).map((r) => r.review_id));
  writeFixtureFile(f.run, assignmentRow.assignment_path, semanticJson(assignment));
  writeFixtureFile(f.run, resultRow.result_path, semanticJson(result));
  writeFixtureFile(f.run, evidencePath, evidence);
  writeFixtureFile(f.run, `verification/harness/${f.subject.owner_stage}/${reviewId}.md`, fixtureCompanion(f.subject, result));
  writeFixtureFile(f.run, SEMANTIC_PATH, semanticLedgerMarkdown(f.ledger));
}

export function addFixtureMaterialFinding(f: SemanticFixture): void {
  const id = 'SEM-0716', reviewId = 'VER-0716', materialUse: MaterialUseInput = {
    requirements: [{ object_id: 'OBJ-0002', feature: 'formal-structure', binding_ids: ['BND-0001'] }],
    use_state: 'CANNOT_DETERMINE', fidelity_claim: 'none', limitation_refs: ['OBJ-0002'], reason: 'Grouping is absent from the flattened text capture.',
  };
  const semantics: Semantics = { atomicity: 'CANNOT_DETERMINE', units: [], contexts: [], couplings: [], relation_proposals: [],
    unresolved_findings: [{ finding_id: 'F1', field_path: '/semantics/atomicity', code: 'material-unavailable', anchor_ids: [],
      material_requirement_indexes: [0], unknown_dimension: 'none', missing: materialUse.reason, requested_context: [] }] };
  const entry: SemanticEntry = { output_kind: 'material-candidate', output_index: 0, review_mode: 'proposal', origin_unit_refs: [], anchors: [], semantics };
  const returned = { ...f.returned, producer_invocation_id: 'manual-material-0716', packets: [], walk_intervals: [], extraction_events: [],
    material_findings: [{ object_id: 'OBJ-0002', material_use: materialUse }], semantic_units: [entry] };
  const producer = { call_id: 'manual-material-0716', context_id: 'manual-material-pass-0716',
    raw_return_hash: materialHash(semanticJson(returned)), output_kind: entry.output_kind, output_index: 0 };
  const producerPath = 'verification/harness/semantic-process/producer-0716.json';
  writeFixtureFile(f.run, producerPath, semanticJson(producer));
  writeFixtureFile(f.run, `verification/harness/semantic-process/${producer.call_id}.raw.json`, semanticJson(returned));
  const model = loadRun(f.run), material = readRepresentationContext(model);
  const use: MaterialRow = { use_id: 'USE-0716', owner_stage: 'S2', subject_kind: 'OBJ', subject_id: 'OBJ-0002',
    basis_packet_ids: '[]', requirements: semanticJson(materialUse.requirements), use_state: materialUse.use_state,
    fidelity_claim: materialUse.fidelity_claim, limitation_refs: semanticJson(materialUse.limitation_refs), reason: materialUse.reason,
    established_by: 'synthetic-producer', review_subject_digest: '', reviewed_by: 'none' };
  use.review_subject_digest = representationUseDigest(model, material, use);
  writeFixtureFile(f.run, 'ledgers/representation-uses.md', representationUsesMarkdown([...material.uses, use]));
  const subject = buildSemanticSubject(loadRun(f.run), { semantic_id: id, owner_stage: 'S2', subject_kind: 'material-only',
    review_mode: 'proposal', predecessor_semantic_id: 'none', producer_binding_hash: semanticProducerBinding(producer),
    reviewer_profile: MANUAL_REVIEWER, output_binding: { kind: 'material-only', object_id: 'OBJ-0002' },
    origin_unit_refs: [], origin_context: [], anchors: [], semantics, material_use: materialUse,
    material_views: semanticMaterialViews(loadRun(f.run), [use]), lineage_context: [], relation_context: [], ambiguity_context: [] });
  const digest = materialHash(semanticJson(subject));
  const assignment: SemanticAssignment = { format: SEMANTIC_ASSIGNMENT_FORMAT, semantic_id: id, subject_digest: digest,
    review_id: reviewId, role: 'verifier-l2s', profile_digest: null, invocation_id: `manual-pass-${reviewId}`,
    producer_binding_hash: subject.producer_binding_hash, execution_kind: 'manual-separate-pass' };
  writeFixtureFile(f.run, semanticSubjectPath(id), semanticJson(subject));
  f.ledger.subjects.push({ semantic_id: id, owner_stage: 'S2', subject_kind: 'material-only', subject_path: semanticSubjectPath(id),
    subject_digest: digest, predecessor_semantic_id: 'none', producer_receipt_ref: `${producerPath}@${materialHash(semanticJson(producer))}` });
  f.ledger.resolutions.push({ resolution_id: 'SMR-0716', semantic_id: id, outcome: 'not-admitted', review_ids: semanticJson([reviewId]),
    canonical_refs: '[]', origin_unit_refs: '[]', followup_semantic_ids: '[]' });
  fixtureReview({ run: f.run, source: f.source, subject, entry, returned, producer, assignment, result: fixtureResult(subject), ledger: f.ledger }, fixtureResult(subject));
}
