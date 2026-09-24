#!/usr/bin/env node
import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, chmodSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, relative } from 'node:path';
import { tmpdir } from 'node:os';
import { assembleBundles } from '../../../scripts/assemble-bundles.ts';
import { loadRun } from '../../../scripts/lib/run-model.ts';
import { RELATION_FORMAT, RELATION_TABLE_HEADER } from '../../../scripts/lib/relations.ts';
import { materialHash, materialFragmentsHash, readRepresentationContext, representationMarkdown, representationUsesMarkdown, representationUseDigest, type MaterialRow } from '../../../scripts/lib/source-representation.ts';
import {
  SEMANTIC_PATH, SEMANTIC_TASK, SEMANTIC_ASSIGNMENT_FORMAT, buildSemanticSubject, emptySemanticLedger,
  semanticJson, semanticProducerSelections, semanticProducerView, semanticProducerViewPaths, semanticProducerTask,
  semanticProducerBinding, semanticSubjectPath, semanticMaterialViews, semanticLedgerMarkdown, semanticAssignmentPath,
  semanticResultPath, semanticStageSeal, validateSemanticRun, type SemanticAssignment, type SemanticOperation,
  semanticOriginProjection, semanticClaimCell, semanticClosureHash,
  parseSemanticLedger, parseSemanticJson, semanticUnresolvedSummary, type Semantics, type SemanticSubject, type SemanticResult,
} from '../../../scripts/lib/semantic-review.ts';
import { makeSemanticFixture, fixtureResult, fixtureCompanion, fixtureTable, SEMANTIC_TEST_ROOT, writeFixtureFile } from '../../../scripts/semantic-fixture-support.ts';
import { type LoaRunState, type LoaRoleId, type JsonValue } from '../src/types.ts';
import type { ValidatedWorkerReturn } from '../src/worker-return.ts';

const RUNTIME = process.argv.includes('--runtime') || process.env.SEMANTIC_RUNTIME_TEST === '1';
const adapterModule = (name: string): string => new URL(RUNTIME ? `../../../runtime-js/adapters/loa/src/${name}.js` : `../src/${name}.ts`, import.meta.url).href;
const { verifyAndLoadLoaBundle } = await import(adapterModule('core-loader')) as typeof import('../src/core-loader.ts');
const { captureRuntimeSnapshot, loadLoaProfile, defaultProfilePath, validateResolvedHost } = await import(adapterModule('runtime-snapshot')) as typeof import('../src/runtime-snapshot.ts');
const { readJsonFile, stableJson, walkRegularFiles } = await import(adapterModule('fs')) as typeof import('../src/fs.ts');
const { readRunState, writeRunState } = await import(adapterModule('run-control')) as typeof import('../src/run-control.ts');
const { assembleWorkerBundle, coreBlindPolicyReference } = await import(adapterModule('worker-bundle')) as typeof import('../src/worker-bundle.ts');
const { dispatchLoaWorker } = await import(adapterModule('worker-dispatch')) as typeof import('../src/worker-dispatch.ts');
const { validateWorkerReturn } = await import(adapterModule('worker-return')) as typeof import('../src/worker-return.ts');
const { LedgerWriter, recoverPendingSemanticTransactions } = await import(adapterModule('ledger-writer')) as typeof import('../src/ledger-writer.ts');
const ROOT = SEMANTIC_TEST_ROOT, TEMP = mkdtempSync(join(tmpdir(), 'aleph-semantic-process-'));
const TIME = '2026-09-12T12:00:00.000Z', clock = { now: () => TIME }, cases: string[] = [];
const recoveryModule = adapterModule('ledger-writer'), recoveryNode = RUNTIME && process.env.SEMANTIC_NODE20 || process.execPath;
function pass(name: string): void { cases.push(name); console.log(`PASS ${name}`); }
function beforeWrite(next: Record<string, string>) {
  return { files: Object.fromEntries(Object.keys(next).map((path) => [path, existsSync(join(run, path)) ? readFileSync(join(run, path)) : null])),
    state: readFileSync(join(run, 'control/run-state.json')), chain: readFileSync(join(run, 'control/ledger-chain.jsonl')) };
}
function probePrepared(name: string, transactionName: string, before: ReturnType<typeof beforeWrite>, partial: number, material = false): void {
  const copy = recoveryCopy(name), transaction = JSON.parse(readFileSync(join(run, 'control/transactions', transactionName), 'utf8'));
  writeFixtureFile(copy, `control/transactions/${transactionName}`, semanticJson({ ...transaction, status: 'prepared' }));
  const writes = transaction.plan.writes as Array<{ path: string; after_base64: string }>;
  for (const [i, write] of writes.entries()) if (i >= partial) {
    const bytes = before.files[write.path];
    if (bytes === null) rmSync(join(copy, write.path)); else writeFixtureFile(copy, write.path, bytes);
  }
  writeFixtureFile(copy, 'control/ledger-chain.jsonl', before.chain);
  writeFixtureFile(copy, 'control/run-state.json', before.state);
  const recovered = spawnSync(recoveryNode, ['--input-type=module', '-e',
    'const [m,r,f]=process.argv.slice(1); (await import(m))[f](r);', recoveryModule, copy,
    material ? 'recoverPendingMaterialTransactions' : 'recoverPendingSemanticTransactions'], { encoding: 'utf8' });
  assert.equal(recovered.status, 0, recovered.stderr);
  for (const write of writes) assert(readFileSync(join(copy, write.path)).equals(Buffer.from(write.after_base64, 'base64')));
  assert(readFileSync(join(copy, 'control/run-state.json')).equals(readFileSync(join(run, 'control/run-state.json'))));
  pass(`fresh subprocess recovers ${name}`);
}
const assembled = assembleBundles(ROOT, join(TEMP, 'bundles'));
assert.equal(assembled.result, 'PASS', assembled.errors.join('; '));
const bundle = verifyAndLoadLoaBundle(join(TEMP, 'bundles/aleph-for-loa'));
const profile = loadLoaProfile(defaultProfilePath(bundle.root));
const host = validateResolvedHost(readJsonFile(join(ROOT, 'adapters/loa/tests/fixtures/host-capabilities.json')), profile.value, { allowSimulation: true });
const run = join(TEMP, 'run'), f = makeSemanticFixture(run);
writeFixtureFile(run, 'ledgers/relations.md', `# Typed Relations\n\n- relation_format: ${RELATION_FORMAT}\n\n`
  + fixtureTable([...RELATION_TABLE_HEADER], []));
// A declared supplied structure exercises an independent L2F obligation. These
// bytes are synthetic inputs, not an inferred parse or a renderer invocation.
const inventory = readRepresentationContext(loadRun(run)).inventory, asset = Buffer.from('Synthetic supplied formal structure.');
writeFixtureFile(run, 'corpus/representation-assets/AST-0900.txt', asset);
inventory.assets.push({ asset_id: 'AST-0900', representation_id: 'REP-0001', role: 'structure-export',
  locus: 'corpus/representation-assets/AST-0900.txt', media_type: 'text/plain', encoding: 'utf8', byte_length: String(asset.length), content_hash: materialHash(asset) });
inventory.provenance.push({ provenance_id: 'RPR-0900', representation_id: 'REP-0001', type: 'supplied-structure',
  actor: 'synthetic-supplier', tool: 'unknown', tool_version: 'unknown', input_refs: '["SRC-701"]', output_refs: '["AST-0900"]',
  parameters_asset_id: 'none', declaration_asset_id: 'AST-0900' });
inventory.bindings.push({ binding_id: 'BND-0900', representation_id: 'REP-0001', carrier_id: 'SRC-701', start_byte: '0', end_byte: String(f.source.length),
  page_id: 'none', region_id: 'none', byte_role: 'frozen-source-bytes', fragment_hash: materialHash(f.source), exact_bytes_base64: f.source.toString('base64') });
inventory.objects.push({ object_id: 'OBJ-0900', representation_id: 'REP-0001', kind: 'formal', parent_id: 'OBJ-0001', state: 'available', reason: 'none',
  provenance_id: 'RPR-0900', binding_ids: '["BND-0900"]', content_hash: materialFragmentsHash([f.source]),
  coordinates: '{"notation":"source-markup","structure_ids":[],"structure_state":"available"}' });
inventory.associations.push({ association_id: 'ASC-0900', representation_id: 'REP-0001', kind: 'caption-for', subject_id: 'OBJ-0900',
  target_ids: '[]', state: 'unsupported', reason: 'No supplied caption.', provenance_id: 'RPR-0900' });
const inventoryBytes = representationMarkdown(inventory);
writeFixtureFile(run, 'corpus/representations.md', inventoryBytes);
writeFixtureFile(run, 'run-manifest.md', readFileSync(join(run, 'run-manifest.md'), 'utf8')
  .replace(/representation_inventory_hash: sha256:[0-9a-f]{64}/u, `representation_inventory_hash: ${materialHash(inventoryBytes)}`));
f.subject.material_use!.requirements.push({ object_id: 'OBJ-0900', feature: 'formal-structure', binding_ids: ['BND-0900'] });
(f.returned.packets as Array<Record<string, unknown>>)[0].material_use = f.subject.material_use;
const capture = Object.fromEntries(['ledgers/packet-index.md', 'ledgers/source-walk.md'].map((path) =>
  [path, readFileSync(join(run, path), 'utf8').replaceAll('manual-producer-0701', 'CALL-PRODUCER')]));
const uses = readRepresentationContext(loadRun(run)).uses;
uses[0].requirements = semanticJson(f.subject.material_use!.requirements);
uses[0].review_subject_digest = representationUseDigest(loadRun(run), readRepresentationContext(loadRun(run)), uses[0]);
// Only a disposable test run is reset to its pre-capture state. The repository
// worktree and preserved adapter workstream are never modified by this suite.
rmSync(join(run, 'verification'), { recursive: true });
rmSync(join(run, 'control/runtime'), { recursive: true });
for (const path of Object.keys(capture)) writeFixtureFile(run, path, capture[path].replace(/^\| (?:PKT|EVID|FRAG|WLK|EVT|CUR|GAP|SRC)-\d+ \|.*\n/gmu, ''));
writeFixtureFile(run, 'ledgers/representation-uses.md', representationUsesMarkdown([]));
let ledger = emptySemanticLedger();
writeFixtureFile(run, SEMANTIC_PATH, semanticLedgerMarkdown(ledger));
const runtime = captureRuntimeSnapshot({ runId: 'RUN-semantic-unit-review', bundle, profile, host, capturedAt: TIME, outputPath: join(run, 'control/runtime/snapshot.json') });
const state: LoaRunState = {
  format: 'aleph-loa-run-state/v1', run_id: 'RUN-semantic-unit-review', mode: 'agent', full_mode: 'fixture-simulated',
  identity: { core: bundle.lock.core, adapter: bundle.lock.adapter,
    bundle: { ...bundle.lock.bundle, lock_digest: bundle.lock.lock_digest, lock_ref: 'control/original-bundle.lock.json', installation_ref: bundle.root },
    checker_digest: bundle.lock.checker_digest, adapter_protocol_version: bundle.lock.adapter_protocol_version,
    run_format_version: bundle.lock.run_format_version, host: host.host, profile: { id: profile.value.id, digest: profile.digest },
    models: Object.fromEntries(Object.entries(profile.value.role_mappings).map(([role, mapping]) => [role, host.models[mapping.model_slot]])) as LoaRunState['identity']['models'],
    runtime: { snapshot_ref: 'control/runtime/snapshot.json', digest: runtime.tree_digest } },
  corpus: { state: 'frozen', inventory_ref: 'corpus/manifest.md', tree_digest: materialHash(f.source) },
  execution: { core_state: 'DISTILLING', stage: 'S2', stage_status: 'running', gate: null, halt: null,
    resume: { sequence: '0', checkpoint_digest: '', last_verified_at: TIME } },
  ledger: { writer_id: 'loa-orchestrator', sequence: '0', chain_head: materialHash(Buffer.alloc(0)) },
};
writeRunState(run, state);
writeFixtureFile(run, 'control/original-bundle.lock.json', readFileSync(join(bundle.root, 'bundle.lock.json')));
let manifest = readFileSync(join(run, 'run-manifest.md'), 'utf8');
for (const [key, value] of Object.entries({ mode: 'agent', core_digest: state.identity.core.tree_digest,
  adapter_id: state.identity.adapter.id, adapter_version: state.identity.adapter.version, adapter_digest: state.identity.adapter.tree_digest,
  bundle_id: state.identity.bundle.id, bundle_digest: state.identity.bundle.digest, bundle_lock_ref: state.identity.bundle.lock_ref,
  checker_digest: state.identity.checker_digest, host_identity: `${host.host.id}@${host.host.version}+${host.host.build_id}`,
  runtime_snapshot_digest: runtime.tree_digest })) manifest = manifest.replace(new RegExp(`^- ${key}: .+$`, 'mu'), `- ${key}: ${value}`);
manifest = manifest.replace('| human |', `| ${stableJson(state.identity.models)} |`)
  .replace('| n/a (core-manual) |', `| ${profile.value.id} @ ${profile.digest} |`)
  .replace('| n/a (manual) |', `| ${stableJson(state.identity.models)} |`);
writeFixtureFile(run, 'run-manifest.md', manifest);
for (const name of ['calibration-answer', 'producer-rationale', 'authority-observation', 'unrelated-source', 'downstream-narrative', 'expected-disposition']) {
  writeFixtureFile(run, `verification/withheld-${name}.md`, `WITHHELD-CANARY-${name}`);
}
function worker(callId: string, role: LoaRoleId, raw: JsonValue, allowlist: string[], task: string, producerContext: string | null = null) {
  const state = readRunState(run), coreRef = coreBlindPolicyReference(bundle, role, state.execution.stage);
  const withheld = walkRegularFiles(run).map((path) => relative(run, path)).filter((path) => !path.startsWith('control/') && !allowlist.includes(path))
    .map((selector) => ({ selector, core_ref: coreRef }));
  const sealed = assembleWorkerBundle({ bundle, runDir: run, callId, runId: state.run_id, stage: state.execution.stage, role,
    kind: role.startsWith('verifier-') ? 'refuter' : 'producer', allowlist, withheld, taskLine: task,
    modelIdentity: state.identity.models[role], producerContextId: producerContext });
  const result = dispatchLoaWorker({ workerBundleRoot: sealed.root, returnRoot: join(run, 'control/worker-returns', callId), hostCapabilities: host,
    host: { invokeFreshContext(invocation) {
      assert.equal(invocation.inherit_context, false); assert.deepEqual(invocation.writable_paths, []);
      for (const attachment of invocation.request.allowlist) assert(!readFileSync(join(sealed.root, attachment.attachment_path)).includes('WITHHELD-CANARY'));
      assert(!invocation.request.task_line.includes('WITHHELD-CANARY'));
      return { receipt: { format: 'aleph-loa-worker-dispatch/v1', call_id: callId, context_id: `CTX-${callId}`, producer_context_id: producerContext,
        fresh_context: true, inherited_context: false, filesystem: 'bundle-read-only', model_identity: invocation.model_identity,
        simulation: { kind: 'fixture-simulated' } }, structured_return: raw };
    } } });
  assert.equal(result.report.result, 'PASS', result.report.errors.join('; '));
  assert(result.validated);
  return { ...result, validated: result.validated };
}
const paths = semanticProducerViewPaths('CALL-PRODUCER');
const selections = semanticProducerSelections(loadRun(run), 'extractor', 'S2', { source_id: 'SRC-701' });
const view = semanticProducerView(loadRun(run), 'extractor', 'S2', selections);
writeFixtureFile(run, paths.selections, semanticJson(selections)); writeFixtureFile(run, paths.view, view.bytes);
const produced = worker('CALL-PRODUCER', 'extractor', { ...f.returned, producer_invocation_id: 'CALL-PRODUCER' } as JsonValue,
  [paths.view, ...view.assets.map((a) => a.path)].sort(), semanticProducerTask('extractor', 'S2'));
pass('actual sealed extractor fixture dispatch and portable acceptance preserve listed semantic key order');
const writer = new LedgerWriter(run, clock);
writer.appendMaterialUse(produced.validated, uses[0], () => capture);
pass('accepted producer reaches Core raw PKT/USE/source-walk capture transaction in fixture simulation');
const producer = { call_id: produced.validated.callId, context_id: produced.validated.contextId!, raw_return_hash: produced.validated.rawDigest,
  output_kind: 'packet-candidate', output_index: 0 };
const producerPath = 'control/worker-returns/CALL-PRODUCER/semantic-producer.json';
writeFixtureFile(run, producerPath, semanticJson(producer));
const subject = buildSemanticSubject(loadRun(run), { semantic_id: 'SEM-0701', owner_stage: 'S2', subject_kind: 'packet-group', review_mode: 'proposal',
  predecessor_semantic_id: 'none', producer_binding_hash: semanticProducerBinding(producer),
  reviewer_profile: { profile_id: profile.value.id, profile_digest: profile.digest, role: 'verifier-l2s', model_identity: { ...readRunState(run).identity.models['verifier-l2s'] } },
  output_binding: { kind: 'packet-group', evidence_keys: ['EVID-0701'], packet_ids: ['PKT-0701'] }, origin_unit_refs: [], origin_context: [],
  anchors: f.entry.anchors, semantics: f.entry.semantics, material_use: f.subject.material_use, material_views: semanticMaterialViews(loadRun(run), uses),
  lineage_context: [], relation_context: [], ambiguity_context: [] });
const digest = materialHash(semanticJson(subject));
function write(operation: SemanticOperation, recordId: string, next: Record<string, string>, reviews: ValidatedWorkerReturn[] = []) {
  const before = beforeWrite(next);
  const plan = writer.executeSemanticWrite({ producer: produced.validated, reviews, semantic_id: subject.semantic_id, subject_digest: digest,
    operation, record_id: recordId, next, prerequisite_paths: [] });
  if (['reserve-subject', 'assign-review', 'record-review'].includes(operation)) {
    const name = `TXN-semantic-${materialHash(plan.key).slice(7)}.json`;
    probePrepared(`${operation}-publication`, name, before, 1);
    if (operation === 'reserve-subject') probePrepared('prepared-reservation-before-publication', name, before, 0);
  }
  return plan;
}
ledger.subjects.push({ semantic_id: subject.semantic_id, owner_stage: 'S2', subject_kind: 'packet-group', subject_path: semanticSubjectPath(subject.semantic_id),
  subject_digest: digest, predecessor_semantic_id: 'none', producer_receipt_ref: `${producerPath}@${materialHash(semanticJson(producer))}` });
write('reserve-subject', subject.semantic_id, { [semanticSubjectPath(subject.semantic_id)]: semanticJson(subject), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
pass('Core semantic reservation retains exact authentic producer binding before dispatch');
const assignment: SemanticAssignment = { format: SEMANTIC_ASSIGNMENT_FORMAT, semantic_id: subject.semantic_id, subject_digest: digest,
  review_id: 'VER-0701', role: 'verifier-l2s', profile_digest: profile.digest, invocation_id: 'CALL-L2S',
  producer_binding_hash: subject.producer_binding_hash, execution_kind: 'fixture-simulated' };
ledger.assignments.push({ review_id: assignment.review_id, semantic_id: subject.semantic_id, assignment_path: semanticAssignmentPath(assignment.review_id),
  assignment_digest: materialHash(semanticJson(assignment)) });
write('assign-review', assignment.review_id, { [semanticAssignmentPath(assignment.review_id)]: semanticJson(assignment), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
const result = fixtureResult(subject), reviewed = worker('CALL-L2S', 'verifier-l2s', result as unknown as JsonValue,
  [semanticSubjectPath(subject.semantic_id)], SEMANTIC_TASK, producer.context_id);
pass('separate sealed L2S invocation sees exact subject; six withheld canaries absent from actual request and accessible files');
const evidencePath = relative(run, reviewed.dispatchRecordPath);
ledger.results.push({ review_id: assignment.review_id, semantic_id: subject.semantic_id, result_path: semanticResultPath(assignment.review_id),
  result_digest: materialHash(semanticJson(result)), execution_kind: 'fixture-simulated',
  execution_evidence_ref: `${evidencePath}@${materialHash(readFileSync(reviewed.dispatchRecordPath))}` });
write('record-review', assignment.review_id, { [semanticResultPath(assignment.review_id)]: semanticJson(result),
  [`verification/harness/S2/${assignment.review_id}.md`]: fixtureCompanion(subject, result), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) }, [reviewed.validated]);
ledger.resolutions.push({ resolution_id: 'SMR-0701', semantic_id: subject.semantic_id, outcome: 'admitted', review_ids: '["VER-0701"]',
  canonical_refs: '["PKT-0701"]', origin_unit_refs: '[]', followup_semantic_ids: '[]' });
const next = { [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) };
write('admit', 'SMR-0701', next, [reviewed.validated]);
assert.deepEqual(validateSemanticRun(loadRun(run)).executions, ['fixture-simulated']);
const stateBefore = readFileSync(join(run, 'control/run-state.json'));
write('admit', 'SMR-0701', next, [reviewed.validated]);
assert(readFileSync(join(run, 'control/run-state.json')).equals(stateBefore));
assert.throws(() => write('admit', 'SMR-0701', { [SEMANTIC_PATH]: `${next[SEMANTIC_PATH]}\n` }, [reviewed.validated]), /SEM_STATE/u);
pass('accepted L2S result and exact resolution commit once; identical retry is a no-op and changed retry is refused');
for (const attack of ['producer-context-reuse', 'forged-simulation']) {
  const before = walkRegularFiles(run).map((path) => [relative(run, path), materialHash(readFileSync(path))]);
  assert.throws(() => validateWorkerReturn({ workerBundleRoot: join(run, 'control/worker-bundles/CALL-L2S'),
    raw: result, dispatchReceipt: { format: 'aleph-loa-worker-dispatch/v1', call_id: 'CALL-L2S',
      context_id: attack === 'producer-context-reuse' ? producer.context_id : 'CTX-ATTACK',
      producer_context_id: producer.context_id, fresh_context: true, inherited_context: false, filesystem: 'bundle-read-only',
      model_identity: readRunState(run).identity.models['verifier-l2s'],
      simulation: { kind: attack === 'forged-simulation' ? 'native-dispatch' as never : 'fixture-simulated' } } }),
  /context|simulation/u);
  assert.deepEqual(walkRegularFiles(run).map((path) => [relative(run, path), materialHash(readFileSync(path))]), before);
  pass(`accepted-return transport refuses ${attack} before changing bytes`);
}
const sealPath = 'verification/harness/semantic-stage-seals/S2.json', seal = semanticJson(semanticStageSeal(ledger, 'S2'));
const s2SealNext = { [sealPath]: seal, 'run-log.md': readFileSync(join(run, 'run-log.md'), 'utf8')
  + `\n## 2026-09-12 12:30 UTC — S2 — exit\n\nsemantic_stage: S2\nsemantic_review_seal_ref: ${sealPath}@${materialHash(seal)}\n` };
const s2SealBefore = beforeWrite(s2SealNext);
const s2SealPlan = writer.executeSemanticWrite({ producer: produced.validated, reviews: [], semantic_id: 'none', subject_digest: materialHash(seal), operation: 'seal',
  record_id: 'S2', next: s2SealNext, prerequisite_paths: [] });
probePrepared('S2-stage-seal-publication', `TXN-semantic-${materialHash(s2SealPlan.key).slice(7)}.json`, s2SealBefore, 1);
pass('Core S2 table-prefix seal is written through the single-writer transaction');
const s3State = readRunState(run); s3State.execution.stage = 'S3'; writeRunState(run, s3State);
writer.append('run-log.md', produced.validated, () => '\n## 2026-09-12 12:40 UTC — S3 — entry\n\nFixture-simulated normalization.\n');
const claim = { normalized_claim: subject.semantics.units[0].proposition, packets: ['PKT-0701'], claim_type: 'factual',
  widen_requests: [], rationale: 'Synthetic preserved candidate.', flags: [], material_use: subject.material_use };
const entry = { output_kind: 'claim-candidate', output_index: 0, review_mode: 'proposal', origin_unit_refs: ['SEM-0701/U1'],
  anchors: f.entry.anchors, semantics: subject.semantics };
const claimReturn = { claims: [claim], no_claim_packets: [], lineage_proposals: [], material_findings: [], semantic_units: [entry] };
const claimPaths = semanticProducerViewPaths('CALL-NORMALIZER');
const claimSelections = semanticProducerSelections(loadRun(run), 'normalizer', 'S3', { origin_semantic_ids: ['SEM-0701'] });
const claimView = semanticProducerView(loadRun(run), 'normalizer', 'S3', claimSelections);
writeFixtureFile(run, claimPaths.selections, semanticJson(claimSelections)); writeFixtureFile(run, claimPaths.view, claimView.bytes);
const normalized = worker('CALL-NORMALIZER', 'normalizer', claimReturn as unknown as JsonValue, [claimPaths.view], semanticProducerTask('normalizer', 'S3'));
pass('S3 producer receives complete assigned origin projection and exact packet group without prior reviewer verdicts');
const claimProducer = { call_id: normalized.validated.callId, context_id: normalized.validated.contextId!, raw_return_hash: normalized.validated.rawDigest,
  output_kind: 'claim-candidate', output_index: 0 };
const claimProducerPath = 'control/worker-returns/CALL-NORMALIZER/semantic-producer.json';
writeFixtureFile(run, claimProducerPath, semanticJson(claimProducer));
const proposed = loadRun(run), material = readRepresentationContext(proposed);
proposed.claims.push({ file: 'ledgers/claim-inventory.md', line: 0, raw: '', cells: [], values: {
  claimId: 'CC-0702', normalizedClaim: semanticClaimCell(claim.normalized_claim), packets: 'PKT-0701', sources: 'SRC-701',
  claimType: 'factual', disposition: '', rationale: '', judgedBy: '', verified: '', status: 'active',
} });
const use: MaterialRow = { use_id: 'USE-0702', owner_stage: 'S3', subject_kind: 'CC', subject_id: 'CC-0702', basis_packet_ids: '["PKT-0701"]',
  requirements: semanticJson(claim.material_use!.requirements), use_state: 'usable', fidelity_claim: 'none', limitation_refs: '[]',
  reason: 'none', established_by: 'CALL-NORMALIZER', review_subject_digest: '', reviewed_by: 'none' };
use.review_subject_digest = representationUseDigest(proposed, material, use);
const claimInventory = readFileSync(join(run, 'ledgers/claim-inventory.md'), 'utf8') + fixtureTable(
  ['claim_id', 'normalized claim', 'packets', 'sources', 'claim_type', 'disposition', 'rationale', 'judged_by', 'verified', 'status'],
  [['CC-0702', claim.normalized_claim, 'PKT-0701', 'SRC-701', 'factual', '', '', '', '', 'active']]).split('\n').slice(2).join('\n');
const reservedMaterial = writer.reserveMaterialUse(normalized.validated, use, () => ({ 'ledgers/claim-inventory.md': claimInventory }));
assert.equal(reservedMaterial.row.review_subject_digest, use.review_subject_digest);
const materialReview = worker('CALL-L2F-NORMALIZER', 'verifier-l2f', { verdict: 'upheld', rationale: 'Synthetic material challenge only.',
  attacks_tried: ['Omitted grouping and glyph-loss challenge.'], evidence_ids: ['PKT-0701'], candidate_evidence: [], missing_for_determination: null, flags: [] },
  [reservedMaterial.review_path], 'Challenge the exact retained representation-use subject.', claimProducer.context_id);
writer.append('verification/harness/VER-0900.md', materialReview.validated, () => '# Material review\n\n'
  + fixtureTable(['field', 'value'], [['lens', 'L2F'], ['stage', 'S3'], ['target', `representation-use-subject:${use.review_subject_digest}`],
    ['shown', reservedMaterial.review_path], ['withheld', 'Producer rationale and other batches.'], ['verdict', 'upheld'], ['consequence', 'Fixture simulation only.']]));
pass('separate accepted L2F challenges the exact reserved material view before CC admission');
const claimSubject = buildSemanticSubject(proposed, { semantic_id: 'SEM-0702', owner_stage: 'S3', subject_kind: 'claim', review_mode: 'proposal',
  predecessor_semantic_id: 'none', producer_binding_hash: semanticProducerBinding(claimProducer), reviewer_profile: subject.reviewer_profile,
  output_binding: { kind: 'claim', reserved_claim_id: 'CC-0702', normalized_claim: claim.normalized_claim, packet_ids: ['PKT-0701'], source_ids: ['SRC-701'], claim_type: 'factual' },
  origin_unit_refs: entry.origin_unit_refs, origin_context: [semanticOriginProjection(subject)], anchors: entry.anchors, semantics: entry.semantics,
  material_use: claim.material_use, material_views: semanticMaterialViews(proposed, [use]), lineage_context: [], relation_context: [], ambiguity_context: [] });
const claimDigest = materialHash(semanticJson(claimSubject));
function writeClaim(operation: SemanticOperation, recordId: string, next: Record<string, string>, reviews: ValidatedWorkerReturn[] = []) {
  return writer.executeSemanticWrite({ producer: normalized.validated, reviews, semantic_id: claimSubject.semantic_id, subject_digest: claimDigest,
    operation, record_id: recordId, next, prerequisite_paths: [] });
}
ledger.subjects.push({ semantic_id: claimSubject.semantic_id, owner_stage: 'S3', subject_kind: 'claim', subject_path: semanticSubjectPath(claimSubject.semantic_id),
  subject_digest: claimDigest, predecessor_semantic_id: 'none', producer_receipt_ref: `${claimProducerPath}@${materialHash(semanticJson(claimProducer))}` });
writeClaim('reserve-subject', 'SEM-0702', { [semanticSubjectPath('SEM-0702')]: semanticJson(claimSubject), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
const claimAssignment: SemanticAssignment = { ...assignment, semantic_id: 'SEM-0702', subject_digest: claimDigest, review_id: 'VER-0702',
  invocation_id: 'CALL-L2S-NORMALIZER', producer_binding_hash: claimSubject.producer_binding_hash };
ledger.assignments.push({ review_id: 'VER-0702', semantic_id: 'SEM-0702', assignment_path: semanticAssignmentPath('VER-0702'), assignment_digest: materialHash(semanticJson(claimAssignment)) });
writeClaim('assign-review', 'VER-0702', { [semanticAssignmentPath('VER-0702')]: semanticJson(claimAssignment), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
const claimResult = fixtureResult(claimSubject), claimReview = worker('CALL-L2S-NORMALIZER', 'verifier-l2s', claimResult as unknown as JsonValue,
  [semanticSubjectPath('SEM-0702')], SEMANTIC_TASK, claimProducer.context_id);
const claimEvidence = relative(run, claimReview.dispatchRecordPath);
ledger.results.push({ review_id: 'VER-0702', semantic_id: 'SEM-0702', result_path: semanticResultPath('VER-0702'), result_digest: materialHash(semanticJson(claimResult)),
  execution_kind: 'fixture-simulated', execution_evidence_ref: `${claimEvidence}@${materialHash(readFileSync(claimReview.dispatchRecordPath))}` });
writeClaim('record-review', 'VER-0702', { [semanticResultPath('VER-0702')]: semanticJson(claimResult),
  'verification/harness/S3/VER-0702.md': fixtureCompanion(claimSubject, claimResult), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) }, [claimReview.validated]);
ledger.resolutions.push({ resolution_id: 'SMR-0702', semantic_id: 'SEM-0702', outcome: 'admitted', review_ids: '["VER-0702"]',
  canonical_refs: '["CC-0702"]', origin_unit_refs: '["SEM-0701/U1"]', followup_semantic_ids: '[]' });
const admission = { [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger),
  'ledgers/claim-inventory.md': claimInventory,
  'ledgers/representation-uses.md': representationUsesMarkdown([...material.uses, { ...use, reviewed_by: 'VER-0900' }]) };
const admissionBefore = Object.fromEntries(Object.keys(admission).map((path) => [path, readFileSync(join(run, path))]));
const stateBeforeAdmission = readFileSync(join(run, 'control/run-state.json')), chainBeforeAdmission = readFileSync(join(run, 'control/ledger-chain.jsonl'));
assert.throws(() => writeClaim('admit', 'SMR-0702', admission), /SEM_ISOLATION/u);
assert.throws(() => writeClaim('admit', 'SMR-0702', admission, [claimReview.validated]), /SEM_ISOLATION/u);
assert.throws(() => writer.appendMaterialUse(normalized.validated, use, () => ({ 'ledgers/claim-inventory.md': admission['ledgers/claim-inventory.md'] })), /SEM_WINDOW/u);
assert.throws(() => writer.append('ledgers/claim-inventory.md', normalized.validated, () => admission['ledgers/claim-inventory.md']), /SEM_WINDOW/u);
for (const [path, before] of Object.entries(admissionBefore)) assert(readFileSync(join(run, path)).equals(before));
pass('static result and generic/material writer bypasses cannot admit a 1.7 claim; refusals preserve canonical bytes');
const admittedPlan = writeClaim('admit', 'SMR-0702', admission, [claimReview.validated, materialReview.validated]);
assert.deepEqual(validateSemanticRun(loadRun(run)).executions, ['fixture-simulated', 'fixture-simulated']);
assert.equal(loadRun(run).claims.filter((c) => c.values.claimId === 'CC-0702').length, 1);
write('admit', 'SMR-0701', next, [reviewed.validated]);
pass('accepted S3 claim, USE and semantic resolution commit together; an older completed retry preserves later rows');
const transactionName = `TXN-semantic-${materialHash(admittedPlan.key).slice(7)}.json`;
const transaction = JSON.parse(readFileSync(join(run, 'control/transactions', transactionName), 'utf8'));
function recoveryCopy(name: string): string {
  const copy = join(TEMP, name); cpSync(run, copy, { recursive: true });
  for (const path of walkRegularFiles(copy)) chmodSync(path, 0o600);
  return copy;
}
for (let partial = 0; partial <= admittedPlan.writes.length + 2; partial++) {
  const copy = recoveryCopy(`interrupted-${partial}`);
  writeFixtureFile(copy, `control/transactions/${transactionName}`, semanticJson({ ...transaction, status: 'prepared' }));
  for (const [index, write] of admittedPlan.writes.entries()) if (index >= partial) writeFixtureFile(copy, write.path, admissionBefore[write.path]);
  if (partial <= admittedPlan.writes.length) writeFixtureFile(copy, 'control/ledger-chain.jsonl', chainBeforeAdmission);
  if (partial <= admittedPlan.writes.length + 1) writeFixtureFile(copy, 'control/run-state.json', stateBeforeAdmission);
  const recovered = spawnSync(recoveryNode, ['--input-type=module', '-e',
    'const [m,r]=process.argv.slice(1); (await import(m)).recoverPendingSemanticTransactions(r);', recoveryModule, copy], { encoding: 'utf8' });
  assert.equal(recovered.status, 0, recovered.stderr);
  for (const [path, text] of Object.entries(admission)) assert.equal(readFileSync(join(copy, path), 'utf8'), text);
  assert(readFileSync(join(copy, 'control/run-state.json')).equals(readFileSync(join(run, 'control/run-state.json'))));
  recoverPendingSemanticTransactions(copy);
  pass(`fresh process recovers composed semantic admission interruption ${partial} from retained exact plan bytes`);
}
for (const failure of ['preimage', 'lost-review', 'fork']) {
  const copy = recoveryCopy(`refused-${failure}`);
  writeFixtureFile(copy, `control/transactions/${transactionName}`, semanticJson({ ...transaction, status: 'prepared' }));
  if (failure === 'preimage') writeFixtureFile(copy, SEMANTIC_PATH, 'changed preimage');
  if (failure === 'lost-review') rmSync(join(copy, 'control/worker-returns/CALL-L2S-NORMALIZER/raw.json'));
  if (failure === 'fork') writeFixtureFile(copy, `control/transactions/TXN-semantic-${'a'.repeat(64)}.json`, semanticJson({ ...transaction, status: 'prepared' }));
  const before = walkRegularFiles(copy).map((path) => [relative(copy, path), materialHash(readFileSync(path))]);
  assert.throws(() => recoverPendingSemanticTransactions(copy), /SEM_STATE|SEM_SUBJECT/u);
  assert.deepEqual(walkRegularFiles(copy).map((path) => [relative(copy, path), materialHash(readFileSync(path))]), before);
  pass(`interrupted ${failure} refuses recovery before further writes`);
}
// A separate proposal remains blocked after two simulated cannot-determine
// returns. A fresh producer then records the uncertainty in a new subject;
// neither its review nor the already usable claim erases that history.
let failedSubject: SemanticSubject | null = null;
for (const unresolved of [false, true]) {
  const number = unresolved ? '0781' : '0780', id = `SEM-${number}`, callId = `CALL-PENDING-${number}`;
  const semantics: Semantics = unresolved ? { atomicity: 'CANNOT_DETERMINE', units: [], contexts: [], couplings: [], relation_proposals: [],
    unresolved_findings: [{ finding_id: 'F1', field_path: '/semantics/atomicity', code: 'atomicity-indeterminate',
      anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: 'The requested local context did not settle the reading.', requested_context: [] }] }
    : structuredClone(subject.semantics);
  const proposal = { ...claimReturn, semantic_units: [{ ...entry, review_mode: unresolved ? 'unresolved-record' : 'proposal', semantics }] };
  const paths = semanticProducerViewPaths(callId), selected = semanticProducerSelections(loadRun(run), 'normalizer', 'S3', { origin_semantic_ids: ['SEM-0701'] });
  const shown = semanticProducerView(loadRun(run), 'normalizer', 'S3', selected);
  writeFixtureFile(run, paths.selections, semanticJson(selected)); writeFixtureFile(run, paths.view, shown.bytes);
  const accepted = worker(callId, 'normalizer', proposal as unknown as JsonValue, [paths.view], semanticProducerTask('normalizer', 'S3'));
  const tuple = { call_id: callId, context_id: accepted.validated.contextId!, raw_return_hash: accepted.validated.rawDigest,
    output_kind: 'claim-candidate', output_index: 0 };
  const receiptPath = `control/worker-returns/${callId}/semantic-producer.json`;
  writeFixtureFile(run, receiptPath, semanticJson(tuple));
  const virtual = loadRun(run);
  virtual.claims.push({ ...proposed.claims.at(-1)!, values: { ...proposed.claims.at(-1)!.values, claimId: `CC-${number}` } });
  const reservedUse: MaterialRow = { ...use, use_id: `USE-${number}`, subject_id: `CC-${number}`, established_by: callId };
  reservedUse.review_subject_digest = representationUseDigest(virtual, readRepresentationContext(virtual), reservedUse);
  const findingFile = semanticResultPath('VER-0780');
  const finding = unresolved ? (parseSemanticJson(readFileSync(join(run, findingFile))) as SemanticResult).unresolved_findings[0] : null;
  const candidate = buildSemanticSubject(virtual, { semantic_id: id, owner_stage: 'S3', subject_kind: 'claim',
    review_mode: unresolved ? 'unresolved-record' : 'proposal', predecessor_semantic_id: failedSubject?.semantic_id || 'none',
    producer_binding_hash: semanticProducerBinding(tuple), reviewer_profile: subject.reviewer_profile,
    output_binding: { ...claimSubject.output_binding, reserved_claim_id: `CC-${number}` } as SemanticSubject['output_binding'],
    origin_unit_refs: entry.origin_unit_refs, origin_context: [semanticOriginProjection(subject)], anchors: entry.anchors, semantics,
    material_use: claim.material_use, material_views: semanticMaterialViews(virtual, [reservedUse]), lineage_context: [], relation_context: [],
    ambiguity_context: unresolved ? [{ kind: 'semantic-finding', reference: `${findingFile}#/unresolved_findings/0@${materialHash(readFileSync(join(run, findingFile)))}`,
      digest: materialHash(semanticJson(finding)), projection: finding as unknown as JsonValue }] : [] });
  const candidateDigest = materialHash(semanticJson(candidate));
  const apply = (operation: SemanticOperation, recordId: string, next: Record<string, string>, reviews: ValidatedWorkerReturn[] = []) =>
    writer.executeSemanticWrite({ producer: accepted.validated, reviews, semantic_id: id, subject_digest: candidateDigest,
      operation, record_id: recordId, next, prerequisite_paths: [] });
  ledger.subjects.push({ semantic_id: id, owner_stage: 'S3', subject_kind: 'claim', subject_path: semanticSubjectPath(id),
    subject_digest: candidateDigest, predecessor_semantic_id: candidate.predecessor_semantic_id,
    producer_receipt_ref: `${receiptPath}@${materialHash(semanticJson(tuple))}` });
  apply('reserve-subject', id, { [semanticSubjectPath(id)]: semanticJson(candidate), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
  const reviewIds = unresolved ? ['VER-0782'] : ['VER-0780', 'VER-0781'], acceptedReviews: ValidatedWorkerReturn[] = [];
  for (const reviewId of reviewIds) {
    const call = `CALL-L2S-${reviewId}`, assignment: SemanticAssignment = { ...claimAssignment, semantic_id: id, subject_digest: candidateDigest,
      review_id: reviewId, invocation_id: call, producer_binding_hash: candidate.producer_binding_hash };
    ledger.assignments.push({ review_id: reviewId, semantic_id: id, assignment_path: semanticAssignmentPath(reviewId),
      assignment_digest: materialHash(semanticJson(assignment)) });
    apply('assign-review', reviewId, { [semanticAssignmentPath(reviewId)]: semanticJson(assignment), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) });
    const result = fixtureResult(candidate);
    if (!unresolved) {
      result.verdict = 'cannot-determine'; result.missing_for_determination = 'The local context does not settle this proposed reading.';
      Object.assign(result.field_reviews.find((r) => r.field_path === '/semantics/contexts')!, { verdict: 'cannot-determine', issue: 'insufficient-context' });
      result.unresolved_findings = [{ finding_id: 'F1', field_path: '/semantics/contexts', code: 'context-insufficient',
        anchor_ids: ['A1'], material_requirement_indexes: [], unknown_dimension: 'none', missing: result.missing_for_determination,
        requested_context: [{ source_id: 'SRC-701', locator: 'L1-L1', purpose: 'local-context' }] }];
    }
    const reviewed = worker(call, 'verifier-l2s', result as unknown as JsonValue, [semanticSubjectPath(id)], SEMANTIC_TASK, tuple.context_id);
    acceptedReviews.push(reviewed.validated);
    const evidencePath = relative(run, reviewed.dispatchRecordPath);
    ledger.results.push({ review_id: reviewId, semantic_id: id, result_path: semanticResultPath(reviewId), result_digest: materialHash(semanticJson(result)),
      execution_kind: 'fixture-simulated', execution_evidence_ref: `${evidencePath}@${materialHash(readFileSync(reviewed.dispatchRecordPath))}` });
    apply('record-review', reviewId, { [semanticResultPath(reviewId)]: semanticJson(result),
      [`verification/harness/S3/${reviewId}.md`]: fixtureCompanion(candidate, result), [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) }, [reviewed.validated]);
  }
  ledger.resolutions.push({ resolution_id: `SMR-${number}`, semantic_id: id, outcome: unresolved ? 'unresolved-recorded' : 'not-admitted',
    review_ids: semanticJson(reviewIds), canonical_refs: '[]', origin_unit_refs: semanticJson(entry.origin_unit_refs), followup_semantic_ids: '[]' });
  apply('resolve', `SMR-${number}`, { [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) }, acceptedReviews);
  if (!unresolved) failedSubject = candidate;
  else {
    assert.notEqual(candidateDigest, materialHash(semanticJson(failedSubject)));
    const summary = semanticUnresolvedSummary(loadRun(run));
    assert(summary.includes('VER-0780:F1') && summary.includes('VER-0781:F1') && summary.includes('producer:F1'));
    assert(!loadRun(run).claims.some((c) => ['CC-0780', 'CC-0781'].includes(c.values.claimId)));
  }
}
pass('two cannot-determine invocations remain retained; new producer and L2S invocation uphold only a linked unresolved record without admitting either reservation');
const s3SealPath = 'verification/harness/semantic-stage-seals/S3.json', s3Seal = semanticJson(semanticStageSeal(ledger, 'S3'));
const s3SealNext = { [s3SealPath]: s3Seal, 'run-log.md': readFileSync(join(run, 'run-log.md'), 'utf8')
  + `\n## 2026-09-12 13:30 UTC — S3 — exit\n\nsemantic_stage: S3\nsemantic_review_seal_ref: ${s3SealPath}@${materialHash(s3Seal)}\n` };
const s3SealBefore = beforeWrite(s3SealNext);
const s3SealPlan = writer.executeSemanticWrite({ producer: normalized.validated, reviews: [], semantic_id: 'none', subject_digest: materialHash(s3Seal), operation: 'seal',
  record_id: 'S3', next: s3SealNext, prerequisite_paths: [] });
probePrepared('S3-stage-seal-publication', `TXN-semantic-${materialHash(s3SealPlan.key).slice(7)}.json`, s3SealBefore, 1);
const s4State = readRunState(run); s4State.execution.stage = 'S4'; writeRunState(run, s4State);
writer.append('run-log.md', normalized.validated, () => '\n## 2026-09-12 13:40 UTC — S4 — entry\n\nFixture empty relation closure.\n');
const c1Before = beforeWrite({ 'run-log.md': '' });
writer.advanceSlice5ClosurePhase('S4-C1-relations-closed');
const c1Name = `TXN-material-${materialHash(`representation-use-closure:${materialHash(readFileSync(join(run, 'ledgers/representation-uses.md')))}`).slice(7)}.json`;
probePrepared('C1-seal-publication', c1Name, c1Before, 1, true);
assert.equal(semanticClosureHash(loadRun(run)), materialHash(readFileSync(join(run, SEMANTIC_PATH))));
const closedBytes = readFileSync(join(run, SEMANTIC_PATH)), closedState = readFileSync(join(run, 'control/run-state.json'));
assert.throws(() => writeClaim('resolve', 'SMR-0703', { [SEMANTIC_PATH]: semanticLedgerMarkdown(ledger) }, [claimReview.validated]), /SEM_WINDOW/u);
assert(readFileSync(join(run, SEMANTIC_PATH)).equals(closedBytes));
assert(readFileSync(join(run, 'control/run-state.json')).equals(closedState));
writer.advanceSlice5ClosurePhase('S4-C1-relations-closed');
pass('C1 seals exact semantic and material ledgers together; later semantic mutation refuses without changing bytes');
{
  const copy = recoveryCopy('retained-stage-erasure');
  validateSemanticRun(loadRun(copy));
  const log = readFileSync(join(copy, 'run-log.md'), 'utf8');
  writeFixtureFile(copy, 'run-log.md', log.slice(0, log.indexOf('## 2026-09-12 13:30 UTC — S3 — exit')));
  assert.equal(readRunState(copy).execution.stage, 'S4');
  assert.throws(() => validateSemanticRun(loadRun(copy)), /SEM_WINDOW S3/u);
  pass('retained S4 stage refuses erased S3 exit and C1 signals; standalone log erasure cannot downgrade host stage facts');
}
for (const kind of ['static-record', 'native-dispatch'] as const) {
  const copy = recoveryCopy(`mislabel-${kind}`), copied = parseSemanticLedger(readFileSync(join(copy, SEMANTIC_PATH), 'utf8'));
  copied.results[0].execution_kind = kind;
  if (kind === 'static-record') {
    const path = 'verification/harness/semantic-process/static.md';
    writeFixtureFile(copy, path, fixtureCompanion(subject, result));
    copied.results[0].execution_evidence_ref = `${path}@${materialHash(readFileSync(join(copy, path)))}`;
    const a = parseSemanticJson(readFileSync(join(copy, semanticAssignmentPath('VER-0701')))) as SemanticAssignment;
    a.execution_kind = kind; writeFixtureFile(copy, semanticAssignmentPath('VER-0701'), semanticJson(a));
    copied.assignments[0].assignment_digest = materialHash(semanticJson(a));
  }
  writeFixtureFile(copy, SEMANTIC_PATH, semanticLedgerMarkdown(copied));
  assert.throws(() => validateSemanticRun(loadRun(copy)), /SEM_ISOLATION/u);
  pass(`${kind} label cannot turn fixture or static evidence into agent freshness`);
}
writeFileSync(join(TEMP, 'report.json'), JSON.stringify({ evidence: 'fixture-simulated transport and writer only; genuine native/model calls NOT RUN',
  modules: RUNTIME ? 'generated runtime-js' : 'TypeScript', recovery_node: recoveryNode,
  recovery_node_version: spawnSync(recoveryNode, ['--version'], { encoding: 'utf8' }).stdout.trim(), cases }, null, 2));
console.log(`Evidence retained: ${TEMP}`);
