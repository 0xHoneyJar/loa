#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadRun } from './lib/run-model.ts';
import { materialHash } from './lib/source-representation.ts';
import { canonicalJsonBytes } from './lib/bundle-format.ts';
import {
  deriveSemanticExecution, semanticJson, semanticLedgerMarkdown, semanticSubjectPath, SEMANTIC_PATH,
  validateSemanticResult, validateSemanticReviewerProfile, semanticUnresolvedSummary,
  semanticProducerSelections, semanticProducerView, semanticProducerTask,
  semanticReturnJsonSchema, semanticOutputContract, validateSemanticReturn, type SemanticRole,
  type SemanticReviewerProfile, type AnchorInput, type Semantics, type LineageContext,
} from './lib/semantic-review.ts';
import { assertSemanticFixture, makeSemanticFixture, MANUAL_REVIEWER, SEMANTIC_TEST_ROOT, writeFixtureFile,
  addFixtureNormalization, addFixtureMaterialFinding, fixtureReview, fixtureResult, fixtureSemantics,
  fixtureTable, makeFragmentSemanticFixture, fixtureUnit,
} from './semantic-fixture-support.ts';
import { ambiguityReviewSubjectJson, searchBasisDigest, type AmbiguityReviewSubject } from './lib/internal-ambiguity.ts';
import { validateWorkerReturnContract } from './lib/worker-return-contract.ts';

const TEMP = mkdtempSync(join(tmpdir(), 'aleph-semantic-review-'));
const baseline = makeSemanticFixture(join(TEMP, 'baseline'));
const report: string[] = [];
function test(name: string, action: () => void): void {
  action(); report.push(name); console.log(`PASS ${name}`);
}
function cli(run: string, token?: string): void {
  const args = ['--root', SEMANTIC_TEST_ROOT, '--run', run, '--json'];
  const result = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'scripts/validate-run.ts'), ...args], { encoding: 'utf8' });
  assert.equal(result.error, undefined, result.error?.message);
  const parsed = JSON.parse(result.stdout);
  const runtime = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'runtime-js/scripts/validate-run.js'), ...args], { encoding: 'utf8' });
  assert.equal(runtime.status, result.status, runtime.stderr);
  assert.deepEqual(JSON.parse(runtime.stdout), parsed, 'TypeScript/runtime positive and negative K2.19 parity');
  if (token) {
    assert.notEqual(result.status, 0);
    assert(parsed.checks.some((c: { id: string; status: string; message: string }) =>
      c.id === 'K2.19' && c.status === 'FAIL' && c.message.includes(token)), JSON.stringify(parsed.checks.filter((c: { status: string }) => c.status === 'FAIL')));
  } else {
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(parsed.result, 'PASS');
  }
}
function copy(name: string): string {
  const run = join(TEMP, name); cpSync(baseline.run, run, { recursive: true }); return run;
}
function profileMutation(name: string, change: (profile: Record<string, unknown>) => void, token = 'SEM_SUBJECT'): void {
  test(name, () => {
    cli(baseline.run);
    const run = copy(name), subject = structuredClone(baseline.subject);
    change(subject.reviewer_profile);
    writeFixtureFile(run, semanticSubjectPath(subject.semantic_id), semanticJson(subject));
    cli(run, token);
  });
}
test('manual valid 1.7 profile and complete K2.19 baseline', () => { assertSemanticFixture(baseline.run); cli(baseline.run); });
profileMutation('manual non-null profile digest refused', (p) => { p.profile_digest = `sha256:${'1'.repeat(64)}`; });
profileMutation('manual model object refused', (p) => { p.model_identity = {}; });
profileMutation('manual wrong profile ID refused', (p) => { p.profile_id = 'manual'; });
profileMutation('manual wrong reviewer role refused', (p) => { p.role = 'verifier-l2'; }, 'SEM_ISOLATION');
profileMutation('manual profile extra key refused', (p) => { p.effort = 'none'; }, 'SEM_FORMAT');
profileMutation('manual profile missing key refused', (p) => { delete p.profile_digest; }, 'SEM_FORMAT');

// Agent/hybrid identities are fixture declarations, with exact pinned bytes.
// No model is called, and these helper tests do not claim native execution.
const modelIdentity = { provider: 'fixture', model_id: 'semantic-test-model-1', resolved_version: 'fixture-1',
  identity_kind: 'fixture-simulated', immutable: true, context: 'fresh-isolated', effort: 'high',
  budget: 'bounded', cache: 'off', batch: 'off', fallback: false };
const mapping = { model_slot: 'judgment', effort: 'high', context_policy: 'fresh-isolated', budget_policy: 'bounded', cache_policy: 'off', batch_policy: 'off' };
const profile = { role_mappings: { 'verifier-l2s': mapping, 'verifier-l2': mapping, extractor: mapping, normalizer: mapping } };
const profileBytes = semanticJson(profile), profileDigest = materialHash(profileBytes);
const agentProfile: SemanticReviewerProfile = { profile_id: 'fixture-semantic-profile', profile_digest: profileDigest, role: 'verifier-l2s', model_identity: modelIdentity };
for (const mode of ['agent', 'hybrid']) {
  const run = copy(mode);
  writeFixtureFile(run, 'control/runtime/profile.json', profileBytes);
  const snapshotBasis = { profile: { id: agentProfile.profile_id, digest: profileDigest, path: 'control/runtime/profile.json' } };
  const snapshotDigest = materialHash(canonicalJsonBytes(snapshotBasis));
  const snapshot = semanticJson({ ...snapshotBasis, tree_digest: snapshotDigest });
  writeFixtureFile(run, 'control/runtime/snapshot.json', snapshot);
  let manifest = readFileSync(join(run, 'run-manifest.md'), 'utf8')
    .replace('- mode: manual', `- mode: ${mode}`).replace('- adapter_id: core-manual', '- adapter_id: loa')
    .replace('- host_identity: human-operator', '- host_identity: fixture-host@1.0.0+fixture')
    .replace(/- runtime_snapshot_digest: .+/u, `- runtime_snapshot_digest: ${snapshotDigest}`)
    .replace('| human |', `| ${semanticJson({ 'verifier-l2s': modelIdentity })} |`)
    .replace('| n/a (core-manual) |', `| ${agentProfile.profile_id} @ ${profileDigest} |`)
    .replace('| n/a (manual) |', `| ${semanticJson({ 'verifier-l2s': modelIdentity })} |`);
  writeFileSync(join(run, 'run-manifest.md'), manifest);
  const model = loadRun(run);
  test(`${mode} exact profile baseline`, () => validateSemanticReviewerProfile(agentProfile, model, 'S2'));
  for (const [name, mutation] of [
    ['null digest', { ...agentProfile, profile_digest: null }],
    ['human model', { ...agentProfile, model_identity: 'human' }],
    ['manual cross-variant', MANUAL_REVIEWER],
  ] as const) test(`${mode} ${name} refused`, () => {
    validateSemanticReviewerProfile(agentProfile, model, 'S2');
    assert.throws(() => validateSemanticReviewerProfile(mutation, model, 'S2'), /SEM_SUBJECT|SEM_FORMAT/u);
  });
}
profileMutation('agent profile refused in manual mode', (p) => Object.assign(p, agentProfile));
test('same human two passes do not establish independent review', () => {
  cli(baseline.run);
  const run = copy('same-actor'), path = 'verification/harness/semantic-process/reviewer-0701.json';
  const evidence = JSON.parse(readFileSync(join(run, path), 'utf8'));
  evidence.reviewer_actor = evidence.producer_actor;
  writeFixtureFile(run, path, semanticJson(evidence));
  const ledger = structuredClone(baseline.ledger);
  ledger.results[0].execution_evidence_ref = `${path}@${materialHash(semanticJson(evidence))}`;
  writeFixtureFile(run, SEMANTIC_PATH, semanticLedgerMarkdown(ledger));
  cli(run, 'SEM_ISOLATION');
});
test('distinct manual actors/passes remain manual-separate-pass', () => {
  const kind = deriveSemanticExecution(loadRun(baseline.run), baseline.subject, baseline.assignment,
    baseline.ledger.results[0].execution_evidence_ref, baseline.producer);
  assert.equal(kind, 'manual-separate-pass'); assert.notEqual(kind, 'native-dispatch');
});
test('manual evidence cannot be relabeled native fresh dispatch', () => {
  cli(baseline.run);
  const run = copy('manual-not-native'), ledger = structuredClone(baseline.ledger);
  ledger.results[0].execution_kind = 'native-dispatch';
  writeFixtureFile(run, SEMANTIC_PATH, semanticLedgerMarkdown(ledger));
  cli(run, 'SEM_ISOLATION');
});
test('reviewer variant changes subject digest and invalidates prior review', () => {
  validateSemanticResult(baseline.result, baseline.subject);
  const subject = { ...baseline.subject, reviewer_profile: agentProfile };
  assert.notEqual(materialHash(semanticJson(subject)), baseline.result.subject_digest);
  assert.throws(() => validateSemanticResult(baseline.result, subject), /SEM_SUBJECT/u);
});
test('native descriptors, portable returns and runtime share exact role contracts and binding limits', () => {
  const normalized = addFixtureNormalization(makeSemanticFixture(join(TEMP, 'portable-normalizer')));
  for (const [role, value] of [['extractor', baseline.returned], ['normalizer', normalized.returned], ['verifier-l2s', baseline.result]] as Array<[SemanticRole, unknown]>) {
    const contract = semanticOutputContract(role), schema = semanticReturnJsonSchema(role, '1.7.0-provisional') as Record<string, unknown>;
    assert.equal(schema.additionalProperties, false);
    assert.deepEqual(schema.required, Object.keys(value as object));
    const dir = join(TEMP, `native-${role}`);
    writeFixtureFile(dir, 'contract.json', semanticJson(contract));
    writeFixtureFile(dir, 'schema.json', semanticJson(schema));
    writeFixtureFile(dir, 'positive.json', semanticJson(value));
    const invalid = { ...(value as object), unsolicited: true };
    writeFixtureFile(dir, 'negative.json', semanticJson(invalid));
    for (const [file, expected] of [['positive.json', 'PASS'], ['negative.json', 'FAIL']]) {
      const args = ['--contract', join(dir, 'contract.json'), '--return', join(dir, file), '--json'];
      const source = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'scripts/validate-worker-return.ts'), ...args], { encoding: 'utf8' });
      const runtime = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, 'runtime-js/scripts/validate-worker-return.js'), ...args], { encoding: 'utf8' });
      assert.deepEqual(JSON.parse(source.stdout), JSON.parse(runtime.stdout));
      const report = JSON.parse(source.stdout);
      assert.equal(report.result, expected); assert.equal(report.binding, 'not-checked');
      assert.equal(validateWorkerReturnContract(readFileSync(join(dir, file)), contract).result, expected);
    }
    writeFixtureFile(dir, 'duplicate-contract.json', semanticJson(contract).replace('"contract_format":',
      '"contract_format":"aleph-semantic-output-contract/v1","contract_format":'));
    for (const path of ['scripts/validate-worker-return.ts', 'runtime-js/scripts/validate-worker-return.js']) {
      const duplicate = spawnSync(process.execPath, [join(SEMANTIC_TEST_ROOT, path), '--contract', join(dir, 'duplicate-contract.json'),
        '--return', join(dir, 'positive.json'), '--json'], { encoding: 'utf8' });
      assert.notEqual(duplicate.status, 0);
      const report = JSON.parse(duplicate.stdout);
      assert.equal(report.result, 'FAIL'); assert(report.errors.some((error: string) => /duplicate/iu.test(error)));
    }
  }
  const s = semanticReturnJsonSchema('verifier-l2s', '1.7.0-provisional') as { properties: Record<string, unknown> };
  assert.deepEqual(s.properties.candidate_evidence, { type: 'array', items: false, maxItems: 0 });
  const context = { model: loadRun(baseline.run), subject: baseline.subject, legal_source_ids: ['SRC-701'], owner_stage: 'S2' as const };
  assert.equal(validateSemanticReturn('verifier-l2s', '1.7.0-provisional', baseline.result, context).binding, 'checked');
  const wrong = { ...baseline.result, subject_digest: `sha256:${'e'.repeat(64)}` };
  assert.equal(validateSemanticReturn('verifier-l2s', '1.7.0-provisional', wrong).result, 'PASS');
  assert.equal(validateSemanticReturn('verifier-l2s', '1.7.0-provisional', wrong, context).result, 'FAIL');
});
const cases = JSON.parse(readFileSync(join(SEMANTIC_TEST_ROOT, 'docs/fixtures/semantic-unit-review/cases.json'), 'utf8')) as
  Array<{ id: string; source: string; anchors: AnchorInput[]; semantics: Semantics; attack: string }>;
assert.equal(new Set(cases.map((c) => c.id)).size, cases.length);
assert.deepEqual([...new Set(cases.map((c) => c.id.split('-')[0]))].sort(),
  Array.from({ length: 22 }, (_, i) => `FX${String(i + 1).padStart(2, '0')}`));
test('FX13 distinct sub-line anchors share one unchanged complete-line PKT', () => {
  const a = 'The counter rose.', b = 'The battery discharged.', source = `${a} ${b}`;
  const anchors: AnchorInput[] = [a, b].map((text, i) => ({ anchor_id: `A${i + 1}`, source_id: 'SRC-701', locator: 'L1-L1',
    start_byte: i === 0 ? 0 : Buffer.byteLength(a) + 1, end_byte: i === 0 ? Buffer.byteLength(a) : Buffer.byteLength(source),
    exact_bytes_base64: Buffer.from(text).toString('base64') }));
  const f = makeSemanticFixture(join(TEMP, 'same-line-anchors'), source, { atomicity: 'multiple-separable',
    units: [fixtureUnit(a, a), fixtureUnit(b, b, 'U2', 'A2')], contexts: [], couplings: [], relation_proposals: [], unresolved_findings: [] }, anchors);
  assert.deepEqual(f.subject.anchors.map((a) => a.packet_ids), [['PKT-0701'], ['PKT-0701']]);
  assertSemanticFixture(f.run); cli(f.run);
});
test('FX02 ordered nonadjacent fragments preserve two PKTs and one exact evidence group', () => {
  const f = makeFragmentSemanticFixture(join(TEMP, 'multiple-fragments'));
  assertSemanticFixture(f.run); cli(f.run);
  assert.deepEqual(f.subject.packet_basis.map((p) => p.packet_id), ['PKT-0701', 'PKT-0702']);
  assert.deepEqual(f.subject.anchors.map((a) => a.packet_ids), [['PKT-0701'], ['PKT-0702']]);
  assert.equal(f.subject.packet_basis[0].evidence_record.join_policy, 'separate-fragments');
});
for (const specimen of cases) test(`${specimen.id} declared structural proposal and fresh-review challenge`, () => {
  assert(specimen.attack.length > 0);
  const f = makeSemanticFixture(join(TEMP, specimen.id), specimen.source, structuredClone(specimen.semantics), specimen.anchors);
  if (f.subject.semantics.atomicity === 'CANNOT_DETERMINE') {
    Object.assign(f.ledger.resolutions[0], { outcome: 'not-admitted', canonical_refs: '[]' });
    writeFixtureFile(f.run, SEMANTIC_PATH, semanticLedgerMarkdown(f.ledger));
    assertSemanticFixture(f.run); cli(f.run);
    return;
  }
  if (specimen.id === 'FX16') {
    addFixtureMaterialFinding(f); assertSemanticFixture(f.run); cli(f.run); return;
  }
  assertSemanticFixture(f.run);
  if (specimen.id === 'FX19') {
    addFixtureNormalization(f, { noClaim: true }); assertSemanticFixture(f.run); cli(f.run); return;
  }
  if (specimen.id === 'FX21') {
    const broad = addFixtureNormalization(f, { proposition: 'Stability proves a permanent causal improvement.', outcome: 'not-admitted' });
    const refutation = fixtureResult(broad.subject);
    refutation.verdict = 'refuted';
    Object.assign(refutation.field_reviews.find((r) => r.field_path === '/semantics/units/0/proposition')!,
      { verdict: 'refuted', issue: 'unsupported-interpretation', explanation: 'This synthetic reviewer challenges the added causal conclusion.' });
    refutation.unresolved_findings = [{ finding_id: 'F1', field_path: '/semantics/units/0/proposition', code: 'interpretation-unsupported',
      anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: 'The cause is not identified.', requested_context: [] }];
    fixtureReview(broad, refutation);
    addFixtureNormalization(f, { number: '0703', predecessor: broad.subject.semantic_id, proposition: 'The observer reported stability.' });
    assertSemanticFixture(f.run); cli(f.run);
    assert(semanticUnresolvedSummary(loadRun(f.run)).includes('VER-0702:F1'));
    return;
  }
  const normalized = [];
  for (const [index, declaredUnit] of specimen.semantics.units.entries()) {
    const unit = structuredClone(declaredUnit); unit.unit_id = 'U1';
    const semantics: Semantics = { atomicity: specimen.semantics.atomicity === 'inseparable-context' ? 'inseparable-context' : 'single-assertion',
      units: [unit], contexts: specimen.semantics.contexts.filter((c) => c.applies_to_unit_ids.includes(declaredUnit.unit_id))
        .map((c, i) => ({ ...c, context_id: `C${i + 1}`, applies_to_unit_ids: ['U1'] })), couplings: [], relation_proposals: [], unresolved_findings: [] };
    normalized.push(addFixtureNormalization(f, { number: String(702 + index).padStart(4, '0'), semantics,
      origins: [`SEM-0701/${declaredUnit.unit_id}`],
      outcome: specimen.id === 'FX09-system-model-interpretation' ? 'not-admitted' : 'admitted' }));
  }
  if (specimen.id === 'FX22') {
    // Membership is a pre-existing synthetic merger proposal, never chosen by
    // the normalizer, reviewer, or deterministic checker.
    const second = addFixtureNormalization(f, { number: '0703', proposition: 'The battery discharged.' });
    const row = { lineage_id: 'LIN-0704', owner_stage: 'S4', type: 'merge', predecessors: 'CC-0702, CC-0703',
      successors: 'CC-0704', basis: 'Synthetic prior merger proposal; no duplicate-equivalence claim.', established_by: 'synthetic-merger' };
    writeFixtureFile(f.run, 'verification/harness/semantic-process/LIN-0704.json', semanticJson(row));
    const predecessors = [normalized[0], second];
    const lineage: LineageContext = { lineage_id: row.lineage_id, row_digest: materialHash(semanticJson(Object.values(row))),
      event: { owner_stage: 'S4', type: 'merge', predecessors: ['CC-0702', 'CC-0703'], successors: ['CC-0704'] },
      unit_definitions: predecessors.map((prior) => {
        assert(prior.subject.output_binding.kind === 'claim');
        const c = prior.subject.output_binding;
        return { kind: 'CC', id: c.reserved_claim_id, projection: { normalized_claim: c.normalized_claim,
          packets: c.packet_ids, sources: c.source_ids, claim_type: c.claim_type } };
      }) };
    const model = loadRun(f.run), options = { origin_semantic_ids: predecessors.map((p) => p.subject.semantic_id), lineage_id: row.lineage_id };
    const selections = semanticProducerSelections(model, 'normalizer', 'S4', options);
    const view = semanticProducerView(model, 'normalizer', 'S4', selections);
    assert.deepEqual(view.context.successor, lineage);
    assert(!view.bytes.includes(row.basis), 'S4 producer must not receive the merger rationale');
    assert.throws(() => semanticProducerView(model, 'normalizer', 'S4',
      semanticProducerSelections(model, 'normalizer', 'S4', { ...options, origin_semantic_ids: options.origin_semantic_ids.slice(0, 1) })), /SEM_WINDOW/u);
    const inventory = readFileSync(join(f.run, 'ledgers/claim-inventory.md'));
    const widened = [...selections, { path: 'ledgers/claim-inventory.md', selector: `bytes:0:${inventory.length}`,
      digest: materialHash(inventory), purpose: 'inspection-context' as const }]
      .sort((a, b) => Buffer.compare(Buffer.from(`${a.path}\0${a.selector}`), Buffer.from(`${b.path}\0${b.selector}`)));
    assert.throws(() => semanticProducerView(model, 'normalizer', 'S4', widened), /SEM_ISOLATION/u);
    const pending = { ...structuredClone(f), run: join(TEMP, 'S4-reservation-boundaries') };
    cpSync(f.run, pending.run, { recursive: true });
    addFixtureNormalization(pending, { number: '0704', proposition: 'The counter rose and the battery discharged.', lineage,
      origins: predecessors.map((p) => `${p.subject.semantic_id}/U1`), outcome: 'not-admitted' });
    cli(pending.run);
    const reservedPath = `verification/harness/semantic-process/${row.lineage_id}.json`;
    writeFixtureFile(pending.run, reservedPath, semanticJson({ ...row, lineage_id: 'LIN-0799' }));
    cli(pending.run, 'SEM_REFERENCE');
    writeFixtureFile(pending.run, reservedPath, semanticJson(row));
    cli(pending.run);
    writeFixtureFile(pending.run, 'ledgers/lineage.md', readFileSync(join(pending.run, 'ledgers/lineage.md'), 'utf8')
      + '| LIN-0799 | S4 | reject | CC-0702 | none | Synthetic retirement before attempted successor reservation. | synthetic-merger |\n');
    cli(pending.run, 'SEM_REFERENCE');
    const successor = addFixtureNormalization(f, { number: '0704', proposition: 'The counter rose and the battery discharged.', lineage,
      origins: predecessors.map((p) => `${p.subject.semantic_id}/U1`) });
    const returned = validateSemanticReturn('normalizer', '1.7.0-provisional', successor.returned, view.context);
    assert.equal(returned.result, 'PASS', returned.errors.join('; '));
    const changed = structuredClone(successor.returned);
    (changed.semantic_units as Array<{ origin_unit_refs: string[] }>)[0].origin_unit_refs = ['SEM-0799/U1'];
    assert.equal(validateSemanticReturn('normalizer', '1.7.0-provisional', changed, view.context).result, 'FAIL');
    writeFixtureFile(f.run, 'ledgers/merge-map.md', '# Duplicate / Merge Map\n\n'
      + fixtureTable(['canonical', 'absorbs', 'basis', 'provenance retained', 'corroboration', 'status'],
        [['CC-0704', 'CC-0702, CC-0703', row.basis, 'SRC-701', 'restatement', 'active']]));
  }
  assertSemanticFixture(f.run); cli(f.run);
});
test('K2.19 accepts structural alternatives and a coherent semantic error without writing evidence', () => {
  const specimens = cases.filter((c) => c.id.startsWith('FX17'));
  assert(specimens.length >= 3 && specimens.some((c) => c.id === 'FX17-coherent-error'));
  const snapshot = (run: string): unknown => {
    const files = (dir: string): string[] => readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
      entry.isDirectory() ? files(join(dir, entry.name)) : [join(dir, entry.name)]);
    return files(run).sort().map((path) => [path, materialHash(readFileSync(path))]);
  };
  assert(new Set(specimens.map((s) => semanticJson(s.semantics))).size >= 3);
  for (const specimen of specimens) {
    const run = join(TEMP, specimen.id), before = snapshot(run);
    cli(run);
    assert.deepEqual(snapshot(run), before, 'deterministic checker must remain read-only');
  }
});
test('dedicated same-source search requires the exact retained request and completed Slice 5 basis', () => {
  const specimen = cases.find((c) => c.id === 'FX05')!;
  const semantics = structuredClone(specimen.semantics);
  const finding = semantics.unresolved_findings.find((f) => f.code === 'referent-unresolved')!;
  finding.requested_context = [{ source_id: 'SRC-701', locator: specimen.anchors[0].locator, purpose: 'same-source-referent-search' }];
  const f = makeSemanticFixture(join(TEMP, 'dedicated-search'), specimen.source, semantics, specimen.anchors);
  Object.assign(f.ledger.resolutions[0], { outcome: 'not-admitted', canonical_refs: '[]' });
  writeFixtureFile(f.run, SEMANTIC_PATH, semanticLedgerMarkdown(f.ledger));
  assertSemanticFixture(f.run);
  const anchor = f.subject.anchors[0], model = loadRun(f.run);
  const completion = model.sourceWalk.completions[0].values;
  const a: AmbiguityReviewSubject = {
    source_entity_kind: 'PKT', source_entity_id: 'PKT-0701', source_id: 'SRC-701',
    expression_locator: anchor.locator, expression_start_byte: anchor.start_byte, expression_end_byte: anchor.end_byte,
    expression_sha256: anchor.selection_hash, expression_bytes_base64: anchor.exact_bytes_base64,
    basis_packet_ids: ['PKT-0701'], search_scope_kind: 'full-same-source',
    search_completion_ref: `SRC-701@${completion.finalCursorId}@${completion.sourceHash}`, search_basis_digest: '',
    candidate_state: 'null-cannot-determine', candidate_refs: [], affected_relation_ids: [], resolution_state: 'unresolved',
    carry_state: 'none', proposed_by: 'invocation:synthetic-search',
  };
  a.search_basis_digest = searchBasisDigest({ source_id: a.source_id, source_hash: materialHash(f.source),
    source_length_bytes: f.source.length, scope_kind: a.search_scope_kind, scope_refs: [], completion_ref: a.search_completion_ref,
    expression_start_byte: a.expression_start_byte, expression_end_byte: a.expression_end_byte, expression_sha256: a.expression_sha256,
    basis_packet_ids: a.basis_packet_ids, candidate_state: a.candidate_state, candidate_refs: a.candidate_refs });
  const workingPath = 'verification/harness/semantic-process/search.json', working = ambiguityReviewSubjectJson(a);
  writeFixtureFile(f.run, workingPath, working);
  const options = { source_id: 'SRC-701', referent_search: {
    request_ref: `${semanticSubjectPath(f.subject.semantic_id)}#/semantics/unresolved_findings/${semantics.unresolved_findings.indexOf(finding)}@${materialHash(semanticJson(f.subject))}`,
    working_subject_ref: `${workingPath}#@${materialHash(working)}`,
  } };
  const selections = semanticProducerSelections(loadRun(f.run), 'extractor', 'S2', options);
  const view = semanticProducerView(loadRun(f.run), 'extractor', 'S2', selections);
  assert.equal(view.context.referent_search?.expression_sha256, anchor.selection_hash);
  assert.notEqual(semanticProducerTask('extractor', 'S2', true), semanticProducerTask('extractor', 'S2'));
  assert(view.bytes.includes('same-source-referent-search'));
  assert.throws(() => semanticProducerView(loadRun(f.run), 'extractor', 'S2',
    selections.filter((s) => s.path !== workingPath)), /SEM_ISOLATION/u);
  const prior = readFileSync(join(f.run, 'ledgers/source-walk.md'), 'utf8');
  writeFixtureFile(f.run, 'ledgers/source-walk.md', prior.replace('| complete |', '| incomplete |'));
  assert.throws(() => semanticProducerSelections(loadRun(f.run), 'extractor', 'S2', options), /SEM_REFERENCE/u);
  writeFixtureFile(f.run, 'ledgers/source-walk.md', prior);
  semanticProducerSelections(loadRun(f.run), 'extractor', 'S2', options);
});
writeFileSync(join(TEMP, 'report.json'), JSON.stringify({ evidence: 'synthetic structural/process declarations; no real model calls', cases: report }, null, 2));
console.log(`Evidence retained: ${TEMP}`);
