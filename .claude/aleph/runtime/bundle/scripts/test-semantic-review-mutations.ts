#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadRun, hasRunCapability, SUPPORTED_RUN_FORMAT_VERSIONS } from './lib/run-model.ts';
import { materialHash } from './lib/source-representation.ts';
import { mdLineSpan, sourceFilePath } from './lib/check-helpers.ts';
import {
  semanticJson, semanticLedgerMarkdown, semanticStageSeal, semanticSubjectPath, semanticResultPath,
  semanticAssignmentPath, semanticProducerBinding, planSemanticWrite, validateSemanticPlan,
  validateSemanticAttachmentDelivery, validateSemanticRun, semanticUnresolvedSummary, SEMANTIC_TASK,
  SEMANTIC_PATH, type SemanticSubject, type SemanticResult, type SemanticWritePlan,
} from './lib/semantic-review.ts';
import {
  assertSemanticFixture, fixtureCompanion, fixtureSemantics, makeSemanticFixture, fixtureResult, fixtureReview,
  SEMANTIC_TEST_ROOT, writeFixtureFile, addFixtureNormalization, sealFixtureSemanticStage, type SemanticFixture,
} from './semantic-fixture-support.ts';

const TEMP = mkdtempSync(join(tmpdir(), 'aleph-semantic-mutations-'));
const base = makeSemanticFixture(join(TEMP, 'baseline'));
const passed: string[] = [];
function cli(run: string, token?: string, id = 'K2.19', onlyNamedCheck = false): void {
  const args = ['--root', SEMANTIC_TEST_ROOT, '--run', run, '--json'];
  const source = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'scripts/validate-run.ts'), ...args], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  assert.equal(source.error, undefined, source.error?.message);
  const parsed = JSON.parse(source.stdout);
  const runtime = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'runtime-js/scripts/validate-run.js'), ...args], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  assert.equal(runtime.error, undefined, runtime.error?.message);
  assert.equal(runtime.status, source.status, runtime.stderr);
  assert.deepEqual(JSON.parse(runtime.stdout), parsed, 'TypeScript/runtime checker drift');
  if (token) {
    assert.notEqual(source.status, 0);
    assert(parsed.checks.some((c: { id: string; status: string; message: string }) => c.id === id && c.status === 'FAIL' && c.message.includes(token)),
      JSON.stringify(parsed.checks.filter((c: { status: string }) => c.status === 'FAIL'), null, 2));
  } else if (onlyNamedCheck) assert(parsed.checks.some((c: { id: string; status: string }) => c.id === id && c.status === 'PASS')
    && !parsed.checks.some((c: { id: string; status: string }) => c.id === id && c.status === 'FAIL'), source.stdout);
  else assert.equal(source.status, 0, source.stdout + source.stderr);
}
function test(name: string, action: () => void): void {
  action(); passed.push(name); console.log(`PASS ${name}`);
}
function copy(name: string): SemanticFixture {
  const run = join(TEMP, name);
  cpSync(base.run, run, { recursive: true });
  return { ...structuredClone(base), run };
}
function subjectChange(f: SemanticFixture, change: (s: SemanticSubject) => void): void {
  change(f.subject);
  writeFixtureFile(f.run, semanticSubjectPath(f.subject.semantic_id), semanticJson(f.subject));
}
function resultChange(f: SemanticFixture, change: (r: SemanticResult) => void): void {
  change(f.result);
  writeFixtureFile(f.run, semanticResultPath(f.assignment.review_id), semanticJson(f.result));
}
function saveLedger(f: SemanticFixture): void { writeFixtureFile(f.run, SEMANTIC_PATH, semanticLedgerMarkdown(f.ledger)); }
function mutation(name: string, token: string, mutate: (fixture: SemanticFixture) => void): void {
  test(name, () => {
    cli(base.run);
    const f = copy(name); mutate(f); cli(f.run, token);
  });
}
function sealS2(f: SemanticFixture): void {
  const path = 'verification/harness/semantic-stage-seals/S2.json', bytes = semanticJson(semanticStageSeal(f.ledger, 'S2'));
  writeFixtureFile(f.run, path, bytes);
  writeFixtureFile(f.run, 'run-log.md', readFileSync(join(f.run, 'run-log.md'), 'utf8')
    + `\n## 2026-09-12 08:30 UTC — S2 — exit\n\nsemantic_stage: S2\nsemantic_review_seal_ref: ${path}@${materialHash(bytes)}\n`);
}
function resealProducer(f: SemanticFixture): void {
  f.producer.raw_return_hash = materialHash(semanticJson(f.returned));
  const receiptPath = f.ledger.subjects[0].producer_receipt_ref.split('@')[0];
  writeFixtureFile(f.run, receiptPath, semanticJson(f.producer));
  writeFixtureFile(f.run, `verification/harness/semantic-process/${f.producer.call_id}.raw.json`, semanticJson(f.returned));
  f.subject.producer_binding_hash = semanticProducerBinding(f.producer);
  const digest = materialHash(semanticJson(f.subject));
  f.assignment.subject_digest = digest; f.assignment.producer_binding_hash = f.subject.producer_binding_hash;
  f.result.subject_digest = digest;
  f.ledger.subjects[0].producer_receipt_ref = `${receiptPath}@${materialHash(semanticJson(f.producer))}`;
  f.ledger.subjects[0].subject_digest = digest;
  f.ledger.assignments[0].assignment_digest = materialHash(semanticJson(f.assignment));
  f.ledger.results[0].result_digest = materialHash(semanticJson(f.result));
  const evidencePath = f.ledger.results[0].execution_evidence_ref.split('@')[0];
  const evidence = JSON.parse(readFileSync(join(f.run, evidencePath), 'utf8'));
  evidence.subject_digest = digest; evidence.shown_digest = digest;
  writeFixtureFile(f.run, evidencePath, semanticJson(evidence));
  f.ledger.results[0].execution_evidence_ref = `${evidencePath}@${materialHash(semanticJson(evidence))}`;
  writeFixtureFile(f.run, semanticSubjectPath(f.subject.semantic_id), semanticJson(f.subject));
  writeFixtureFile(f.run, semanticAssignmentPath(f.assignment.review_id), semanticJson(f.assignment));
  writeFixtureFile(f.run, semanticResultPath(f.assignment.review_id), semanticJson(f.result));
  writeFixtureFile(f.run, 'verification/harness/S2/VER-0701.md', fixtureCompanion(f.subject, f.result));
  saveLedger(f);
}
test('baseline full CLI and runtime PASS', () => { assertSemanticFixture(base.run); cli(base.run); });
mutation('M01 missing facet', 'SEM_FORMAT', (f) => subjectChange(f, (s) => { delete (s.semantics.units[0] as unknown as Record<string, unknown>).scope; }));
mutation('M02 declared atomicity cardinality', 'SEM_ENUM', (f) => subjectChange(f, (s) => { s.semantics.atomicity = 'multiple-separable'; }));
mutation('M03 unknown anchor', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => { s.semantics.units[0].proposition_anchor_ids = ['A9']; }));
mutation('M04 changed frozen bytes', 'SEM_EVIDENCE', (f) => writeFixtureFile(f.run, 'corpus/sources/semantic.txt', 'Changed frozen bytes.'));
mutation('M05 changed proposition without new subject', 'SEM_SUBJECT', (f) => subjectChange(f, (s) => { s.semantics.units[0].proposition = 'A different proposed reading.'; }));
mutation('M06 missing VER companion', 'SEM_REVIEW', (f) => rmSync(join(f.run, 'verification/harness/S2/VER-0701.md')));
mutation('M07 wrong result digest binding', 'SEM_SUBJECT', (f) => resultChange(f, (r) => { r.subject_digest = `sha256:${'0'.repeat(64)}`; }));
mutation('M08 same human self-review', 'SEM_ISOLATION', (f) => {
  const path = f.ledger.results[0].execution_evidence_ref.split('@')[0], evidence = JSON.parse(readFileSync(join(f.run, path), 'utf8'));
  evidence.reviewer_actor = evidence.producer_actor;
  writeFixtureFile(f.run, path, semanticJson(evidence));
  f.ledger.results[0].execution_evidence_ref = `${path}@${materialHash(semanticJson(evidence))}`; saveLedger(f);
});
mutation('M09 unsealed context manifest expansion', 'SEM_SUBJECT', (f) => subjectChange(f, (s) => {
  s.context_manifest.push({ path: 'ledgers/claim-inventory.md', selector: 'row:Candidates:0', digest: s.run_binding.core_digest, purpose: 'inspection-context' });
}));
for (const [id, field] of [['M10', 'qualifiers'], ['M11', 'conditions'], ['M12', 'attribution']] as const) {
  mutation(`${id} missing ${field}`, 'SEM_FORMAT', (f) => subjectChange(f, (s) => { delete (s.semantics.units[0] as unknown as Record<string, unknown>)[field]; }));
}
mutation('M13 invalid modality', 'SEM_ENUM', (f) => subjectChange(f, (s) => {
  s.semantics.units[0].modality = { state: 'present', items: [{ kind: 'actuality-from-possibility', source_text: Buffer.from(s.anchors[0].exact_bytes_base64, 'base64').toString(), anchor_ids: ['A1'] }], basis_anchor_ids: ['A1'] };
}));
mutation('M14 support taxonomy leakage', 'SEM_ENUM', (f) => subjectChange(f, (s) => { s.semantics.units[0].claim_roles.items[0].kind = 'primary-evidence'; }));
test('M15 structurally declared uncertainty cannot be admitted', () => {
  cli(base.run);
  const text = 'The permitted text leaves the scope unsettled.', semantics = fixtureSemantics(text);
  semantics.atomicity = 'CANNOT_DETERMINE';
  semantics.unresolved_findings.push({ finding_id: 'F1', field_path: '/semantics/atomicity', code: 'atomicity-indeterminate',
    anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: 'The frozen wording does not settle the proposed scope.', requested_context: [] });
  const f = makeSemanticFixture(join(TEMP, 'M15'), text, semantics);
  cli(f.run, 'SEM_STATE');
  f.ledger.resolutions[0].outcome = 'not-admitted'; f.ledger.resolutions[0].canonical_refs = '[]'; saveLedger(f);
  cli(f.run);
});
mutation('M16 new relation type refused', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => {
  const subject = { format: 'aleph-relation-review-subject/v1', owner_stage: 'S2', family: 'source-context', type: 'supports',
    source_kind: 'PKT', source_id: 'PKT-0701', target_kind: 'null', target_id: 'none', target_source_id: 'none', target_locator: 'none',
    target_span_hash: 'none', record_state: 'unresolved-target', null_reason: 'target-not-materialized', basis_packet_ids: ['PKT-0701'], proposed_by: 'human:fixture' };
  s.semantics.relation_proposals.push({ subject, review_subject_digest: materialHash(semanticJson(subject)), material_use: s.material_use! });
}));
mutation('M17 missing unresolved finding', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => { s.semantics.units[0].scope.state = 'CANNOT_DETERMINE'; }));
mutation('M18 missing material view', 'SEM_SUBJECT', (f) => subjectChange(f, (s) => { s.material_views = []; }));
mutation('M19 predecessor semantic artifact injection', 'SEM_COMPATIBILITY', (f) => writeFixtureFile(f.run, 'run-manifest.md',
  readFileSync(join(f.run, 'run-manifest.md'), 'utf8').replace('1.7.0-provisional', '1.6.0-provisional')));
mutation('M20 duplicate reservation resolution', 'SEM_ACCOUNTING', (f) => {
  f.ledger.resolutions.push({ ...f.ledger.resolutions[0], resolution_id: 'SMR-0702' }); saveLedger(f);
});
mutation('M21 closure outside C1', 'SEM_WINDOW', (f) => writeFixtureFile(f.run, 'run-log.md',
  readFileSync(join(f.run, 'run-log.md'), 'utf8') + `\nsemantic_review_closure_hash: ${materialHash(semanticLedgerMarkdown(f.ledger))}\n`));
test('M22 Core plan reservation/preimage and changed-key refusal', () => {
  cli(base.run);
  const before = copy('M22-before'), after = copy('M22-after');
  for (const f of [before, after]) {
    rmSync(join(f.run, semanticAssignmentPath(f.assignment.review_id)));
    rmSync(join(f.run, semanticResultPath(f.assignment.review_id)));
    rmSync(join(f.run, semanticSubjectPath(f.subject.semantic_id)));
    f.ledger.assignments = []; f.ledger.results = []; f.ledger.resolutions = [];
  }
  before.ledger.subjects = []; saveLedger(before);
  writeFixtureFile(after.run, semanticSubjectPath(after.subject.semantic_id), semanticJson(after.subject)); saveLedger(after);
  const writes = [SEMANTIC_PATH, semanticSubjectPath(after.subject.semantic_id)].map((path) => {
    const old = path === SEMANTIC_PATH ? readFileSync(join(before.run, path)) : Buffer.alloc(0), bytes = readFileSync(join(after.run, path));
    return { path, before_hash: materialHash(old), after_base64: bytes.toString('base64'), after_hash: materialHash(bytes) };
  });
  const options = { model: loadRun(before.run), proposedModel: loadRun(after.run), stage: 'S2' as const,
    semantic_id: after.subject.semantic_id, subject_digest: materialHash(semanticJson(after.subject)),
    operation: 'reserve-subject' as const, record_id: after.subject.semantic_id, writes, prerequisite_paths: [] };
  const plan = planSemanticWrite(options); validateSemanticPlan(plan);
  assert(plan.prerequisite_hashes.some((ref) => ref.path === 'run-manifest.md'));
  const fork: SemanticWritePlan = structuredClone(plan); fork.semantic_id = 'SEM-0799';
  assert.throws(() => validateSemanticPlan(fork), /SEM_STATE/u);
  const changed = structuredClone(writes); changed[0].before_hash = `sha256:${'0'.repeat(64)}`;
  assert.throws(() => planSemanticWrite({ ...options, writes: changed }), /SEM_STATE/u);
});
test('M23 cumulative capability and genuine predecessor fixture', () => {
  for (const version of SUPPORTED_RUN_FORMAT_VERSIONS) {
    assert.equal(hasRunCapability(version, 'semantic-unit-review'), version === '1.7.0-provisional');
  }
  assert(hasRunCapability('1.6.0-provisional', 'formal-layout-bindings'));
  const legacy = join(SEMANTIC_TEST_ROOT, 'docs/fixtures/formal-layout-bindings/positive'); cli(legacy);
  const run = join(TEMP, 'M23-forbidden-migration'); cpSync(legacy, run, { recursive: true });
  writeFixtureFile(run, 'run-manifest.md', readFileSync(join(run, 'run-manifest.md'), 'utf8').replace('1.6.0-provisional', '1.7.0-provisional'));
  cli(run, 'SEM_FORMAT');
});
test('M24 actual selectors override self-reported counts', () => {
  const f = copy('M24'), clean = copy('M24-clean'); sealS2(clean); cli(clean.run);
  const entries = f.returned.semantic_units as Record<string, unknown>[], packets = f.returned.packets as unknown[];
  packets.push(structuredClone(packets[0])); entries.push({ ...structuredClone(entries[0]), output_index: 1 });
  f.returned.notes = ['Self-reported coverage: one candidate, one review, complete.'];
  resealProducer(f); sealS2(f); cli(f.run, 'SEM_ACCOUNTING');
});
for (const field of ['contexts', 'couplings', 'relation_proposals', 'unresolved_findings'] as const)
  mutation(`M01 absent ${field}`, 'SEM_FORMAT', (f) => subjectChange(f, (s) => { delete (s.semantics as unknown as Record<string, unknown>)[field]; }));
mutation('M02 invalid context kind', 'SEM_ENUM', (f) => subjectChange(f, (s) => {
  s.semantics.contexts.push({ context_id: 'C1', kind: 'evidence' as never, applies_to_unit_ids: ['U1'], anchor_ids: ['A1'],
    material_requirement_indexes: [], use: 'inspection-only' });
}));
mutation('M02 invalid coupling kind', 'SEM_ENUM', (f) => subjectChange(f, (s) => {
  s.semantics.couplings.push({ kind: 'support-edge' as never, unit_ids: ['U1'], anchor_ids: ['A1'], treatment: 'keep-together' });
}));
mutation('M03 unknown source', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => { s.anchors[0].source_id = 'SRC-799'; }));
mutation('M03 unknown material index', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => {
  s.semantics.contexts.push({ context_id: 'C1', kind: 'representation-layout', applies_to_unit_ids: ['U1'], anchor_ids: [],
    material_requirement_indexes: [9], use: 'inspection-only' });
}));
mutation('M04 changed exact selection base64', 'SEM_EVIDENCE', (f) => subjectChange(f, (s) => { s.anchors[0].exact_bytes_base64 = Buffer.from('altered').toString('base64'); }));
mutation('M04 changed selection hash', 'SEM_EVIDENCE', (f) => subjectChange(f, (s) => { s.anchors[0].selection_hash = `sha256:${'e'.repeat(64)}`; }));
mutation('M05 changed reviewed content role', 'SEM_SUBJECT', (f) => subjectChange(f, (s) => { s.semantics.units[0].claim_roles.items[0].kind = 'background-context'; }));
mutation('M06 missing JSON result', 'SEM_REVIEW', (f) => rmSync(join(f.run, semanticResultPath(f.assignment.review_id))));
mutation('M06 missing field review', 'SEM_REVIEW', (f) => resultChange(f, (r) => { r.field_reviews.pop(); }));
mutation('M07 duplicate JSON member', 'SEM_FORMAT', (f) => writeFixtureFile(f.run, semanticResultPath(f.assignment.review_id),
  semanticJson(f.result).replace('"verdict":"upheld"', '"verdict":"upheld","verdict":"upheld"')));
mutation('M07 VER disagrees with result', 'SEM_REVIEW', (f) => writeFixtureFile(f.run, 'verification/harness/S2/VER-0701.md',
  fixtureCompanion(f.subject, { ...f.result, verdict: 'refuted' })));
test('M09 actual forbidden attachment and task bytes refused by Core', () => {
  cli(base.run);
  const attachments = [{ path: semanticSubjectPath(base.subject.semantic_id), bytes: Buffer.from(semanticJson(base.subject)) }];
  validateSemanticAttachmentDelivery(base.subject, SEMANTIC_TASK, attachments);
  assert.throws(() => validateSemanticAttachmentDelivery(base.subject, `${SEMANTIC_TASK} Expected answer: uphold.`, attachments), /SEM_ISOLATION/u);
  assert.throws(() => validateSemanticAttachmentDelivery(base.subject, SEMANTIC_TASK,
    [...attachments, { path: 'ledgers/claim-inventory.md', bytes: Buffer.from('WITHHELD-CANARY') }]), /SEM_ISOLATION/u);
});
for (const [id, field] of [['M10', 'qualifiers'], ['M11', 'conditions'], ['M12', 'attribution']] as const) test(`${id} dropped reviewed item changes subject`, () => {
  const semantics = fixtureSemantics('Usually stable under load, according to the observer.');
  const item = { kind: field === 'qualifiers' ? 'frequency' : field === 'conditions' ? 'condition' : 'source-author',
    source_text: 'Usually stable under load, according to the observer.',
    ...(field === 'attribution' ? { attributed_to: 'the observer' } : {}), anchor_ids: ['A1'] };
  semantics.units[0][field] = { state: 'present', items: [item], basis_anchor_ids: ['A1'] } as never;
  const f = makeSemanticFixture(join(TEMP, `${id}-item`), item.source_text, semantics); cli(f.run);
  subjectChange(f, (s) => { s.semantics.units[0][field] = { state: 'not-expressed', items: [], basis_anchor_ids: ['A1'] }; });
  cli(f.run, 'SEM_SUBJECT');
});
mutation('M13 not-expressed with nonempty modality', 'SEM_ENUM', (f) => subjectChange(f, (s) => {
  s.semantics.units[0].modality.items = [{ kind: 'possible', source_text: s.semantics.units[0].proposition, anchor_ids: ['A1'] }];
}));
test('M15 retained cannot-determine survives a later upheld review', () => {
  const f = copy('M15-second-review'), first = fixtureResult(f.subject);
  first.verdict = 'cannot-determine'; first.missing_for_determination = 'The condition remains ambiguous.';
  Object.assign(first.field_reviews.find((r) => r.field_path === '/semantics/units/0/conditions')!,
    { verdict: 'cannot-determine', issue: 'insufficient-context' });
  first.unresolved_findings = [{ finding_id: 'F1', field_path: '/semantics/units/0/conditions', code: 'condition-indeterminate',
    anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: first.missing_for_determination, requested_context: [] }];
  f.ledger.resolutions[0].outcome = 'not-admitted'; f.ledger.resolutions[0].canonical_refs = '[]';
  fixtureReview(f, first); fixtureReview(f, fixtureResult(f.subject), 'VER-0702'); cli(f.run);
  const clean = readFileSync(join(f.run, SEMANTIC_PATH));
  f.ledger.resolutions[0].outcome = 'admitted'; f.ledger.resolutions[0].canonical_refs = '["PKT-0701"]'; saveLedger(f);
  cli(f.run, 'SEM_REVIEW');
  writeFixtureFile(f.run, SEMANTIC_PATH, clean); cli(f.run);
  rmSync(join(f.run, semanticResultPath('VER-0702'))); cli(f.run, 'SEM_REVIEW');
});
mutation('M17 URL request cannot widen frozen context', 'SEM_REFERENCE', (f) => subjectChange(f, (s) => {
  s.semantics.unresolved_findings.push({ finding_id: 'F1', field_path: '/semantics/contexts', code: 'context-insufficient',
    anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: 'Need context.',
    requested_context: [{ source_id: 'SRC-701', locator: 'https://example.invalid/answer', purpose: 'local-context' }] });
}));
mutation('M20 lost retained assignment row', 'SEM_REVIEW', (f) => { f.ledger.assignments = []; saveLedger(f); });
test('M21 sealed table prefix cannot be rewritten', () => {
  const f = copy('M21-prefix'); sealS2(f); cli(f.run);
  f.ledger.resolutions[0].outcome = 'not-admitted'; f.ledger.resolutions[0].canonical_refs = '[]'; saveLedger(f); cli(f.run, 'SEM_WINDOW');
});
mutation('M07 L2S candidate evidence must remain empty in portable Core', 'SEM_FORMAT',
  (f) => resultChange(f, (r) => { (r.candidate_evidence as unknown[]).push({ fabricated: true }); }));
test('M06 withdrawn outcome cannot hide an unfinished assigned review at exit', () => {
  const f = copy('unfinished-withdrawal'); sealS2(f); cli(f.run);
  // Retain the assignment while the result has not arrived. This is valid
  // pending structure, but a procedural withdrawal cannot close its review.
  rmSync(join(f.run, semanticResultPath('VER-0701')));
  rmSync(join(f.run, 'verification/harness/S2/VER-0701.md'));
  f.ledger.results = [];
  Object.assign(f.ledger.resolutions[0], { outcome: 'not-admitted', review_ids: '[]', canonical_refs: '[]' });
  saveLedger(f);
  writeFixtureFile(f.run, 'run-log.md', readFileSync(join(base.run, 'run-log.md')));
  assert.deepEqual(validateSemanticRun(loadRun(f.run)).pending, ['SEM-0701']);
  sealS2(f); cli(f.run, 'SEM_ACCOUNTING');
});
test('M06 emitted selector without any review cannot close as a withdrawal', () => {
  const f = copy('unreviewed-withdrawal'); sealS2(f); cli(f.run);
  rmSync(join(f.run, semanticAssignmentPath('VER-0701')));
  rmSync(join(f.run, semanticResultPath('VER-0701')));
  rmSync(join(f.run, 'verification/harness/S2/VER-0701.md'));
  f.ledger.assignments = []; f.ledger.results = [];
  Object.assign(f.ledger.resolutions[0], { outcome: 'not-admitted', review_ids: '[]', canonical_refs: '[]' });
  saveLedger(f);
  writeFixtureFile(f.run, 'run-log.md', readFileSync(join(base.run, 'run-log.md')));
  sealS2(f); cli(f.run, 'SEM_ACCOUNTING');
});
test('M21 a later review cannot be appended to an exited stage', () => {
  const f = copy('late-review'); sealS2(f); cli(f.run);
  fixtureReview(f, fixtureResult(f.subject), 'VER-0702');
  cli(f.run, 'SEM_WINDOW');
});
test('M17 section 17 keeps the historical finding after a narrower usable successor', () => {
  const f = makeSemanticFixture(join(TEMP, 'section-17'));
  const broad = addFixtureNormalization(f, { outcome: 'not-admitted', proposition: 'The observation proves a permanent cause.' });
  const refutation = fixtureResult(broad.subject);
  refutation.verdict = 'refuted';
  Object.assign(refutation.field_reviews.find((r) => r.field_path === '/semantics/units/0/proposition')!,
    { verdict: 'refuted', issue: 'unsupported-interpretation' });
  refutation.unresolved_findings = [{ finding_id: 'F1', field_path: '/semantics/units/0/proposition', code: 'interpretation-unsupported',
    anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: 'No cause was established.', requested_context: [] }];
  fixtureReview(broad, refutation);
  addFixtureNormalization(f, { number: '0703', predecessor: broad.subject.semantic_id, proposition: 'The counter was observed to rise.' });
  cli(f.run);
  sealFixtureSemanticStage(f, 'S3');
  writeFixtureFile(f.run, 'run-log.md', readFileSync(join(f.run, 'run-log.md'), 'utf8')
    + `\n## 2026-09-12 11:00 UTC — S4 — closure\n\nclosure_phase: S4-C1-relations-closed\nsemantic_review_closure_hash: ${materialHash(readFileSync(join(f.run, SEMANTIC_PATH)))}\n`);
  writeFixtureFile(f.run, 'run-manifest.md', readFileSync(join(f.run, 'run-manifest.md'), 'utf8')
    .replace('| 3 | DISTILLING |', '| 3 | ASSEMBLED |'));
  const summary = semanticUnresolvedSummary(loadRun(f.run));
  assert(summary.includes('VER-0702:F1') && summary.includes('CANNOT_DETERMINE'));
  writeFixtureFile(f.run, 'precis.md', `## 17. Known gaps and unresolved material\n\n${summary}\n`);
  cli(f.run, undefined, 'K2.19', true);
  // This isolated ASSEMBLED fixture exercises the real K2.19 surface only;
  // it makes no claim to fulfill the unrelated later-stage K2-K6 contracts.
  writeFixtureFile(f.run, 'precis.md', `## 17. Known gaps and unresolved material\n\n${summary.split('\n').filter((line) => !line.includes('VER-0702:F1')).join('\n')}\n`);
  cli(f.run, 'SEM_ACCOUNTING');
});
const predecessors = ['run-slice-2', 'exact-evidence-fragments', 'source-walk-accounting', 'lineage-accounting',
  'typed-relations', 'internal-ambiguity-lifecycle', 'formal-layout-bindings/positive'];
const artifacts = [SEMANTIC_PATH, semanticSubjectPath('SEM-0701'), semanticResultPath('VER-0701'),
  semanticAssignmentPath('VER-0701'), 'verification/harness/semantic-stage-seals/S2.json', 'run-log.md', 'run-manifest.md'];
for (const [index, family] of predecessors.entries()) test(`M19 genuine 1.${index} fixture preserved; canonical injection refused`, () => {
  const original = join(SEMANTIC_TEST_ROOT, 'docs/fixtures', family); cli(original);
  const run = join(TEMP, `legacy-injection-${index}`); cpSync(original, run, { recursive: true });
  const path = artifacts[index];
  if (index >= 5) writeFixtureFile(run, path, readFileSync(join(run, path), 'utf8')
    + `\nsemantic_review_closure_hash: sha256:${'0'.repeat(64)}\n`);
  else writeFixtureFile(run, path, path === SEMANTIC_PATH ? semanticLedgerMarkdown(base.ledger) : semanticJson(base.subject));
  cli(run, 'SEM_COMPATIBILITY');
});
test('FX18 incidental semantic marker strings in synthetic predecessor source bytes remain data', () => {
  const original = join(SEMANTIC_TEST_ROOT, 'docs/fixtures/run-slice-2'); cli(original);
  const run = join(TEMP, 'legacy-corpus-marker'); cpSync(original, run, { recursive: true });
  const path = 'corpus/sources/SRC-101-access-model.md', before = readFileSync(join(run, path));
  const after = Buffer.concat([before, Buffer.from('\nLiteral data: aleph-semantic-review/v1 aleph-semantic-subject/v1 aleph-semantic-assignment/v1 aleph-semantic-result/v1 aleph-semantic-stage-seal/v1 semantic_review_closure_hash\n')]);
  writeFixtureFile(run, path, after);
  writeFixtureFile(run, 'corpus/manifest.md', readFileSync(join(run, 'corpus/manifest.md'), 'utf8').replace(materialHash(before), materialHash(after)));
  // The companion has new captured bytes. Reopen its existing md-lines spans,
  // including the existing last-line newline rule; no predecessor is migrated.
  const model = loadRun(run); let packetText = readFileSync(join(run, 'ledgers/packet-index.md'), 'utf8');
  for (const packet of model.packets) {
    const source = model.corpus.sources.find((s) => s.values.sourceId === packet.values.sourceId)!;
    const match = /^L([0-9]+)-L([0-9]+)$/u.exec(packet.values.locator)!;
    const span = mdLineSpan(sourceFilePath(run, source.values.locus)!, Number(match[1]), Number(match[2]))!;
    packetText = packetText.replace(packet.values.spanHash, materialHash(span.bytes!));
  }
  writeFixtureFile(run, 'ledgers/packet-index.md', packetText);
  cli(run);
});
writeFileSync(join(TEMP, 'report.json'), JSON.stringify({ cases: passed, evidence: 'real checker CLI, synthetic data, source/runtime comparison; no model calls' }, null, 2));
console.log(`Evidence retained: ${TEMP}`);
