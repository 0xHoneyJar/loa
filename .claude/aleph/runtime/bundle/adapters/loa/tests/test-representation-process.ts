#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assembleBundles } from '../../../scripts/assemble-bundles.ts';
import { predecessorSource } from '../../../scripts/compatibility-fixture-source.ts';
import { loadRun } from '../../../scripts/lib/run-model.ts';
import { mdLineSpan } from '../../../scripts/lib/check-helpers.ts';
import { materialFragmentsHash, materialHash, readRepresentationContext, representationMarkdown, representationUseDigest, representationUsesMarkdown, validateRepresentationRun, type MaterialRow } from '../../../scripts/lib/source-representation.ts';
import { verifyAndLoadLoaBundle } from '../src/core-loader.ts';
import { startLoaRun, recordS0AuthorityResponse, resumeLoaRun } from '../src/cli.ts';
import { LedgerWriter, recoverPendingMaterialTransactions } from '../src/ledger-writer.ts';
import { readRunState, writeRunState } from '../src/run-control.ts';
import { snapshotCorpus, verifyCorpusSnapshot } from '../src/intake.ts';
import { readJsonFile, sha256Digest, stableJsonBytes, walkRegularFiles } from '../src/fs.ts';
import { captureRuntimeSnapshot, defaultProfilePath, loadLoaProfile, parseLoaProfile, validateResolvedHost, type LoadedLoaProfile } from '../src/runtime-snapshot.ts';
import { LOA_ROLE_IDS, LOA_RUN_STATE_FORMAT, type LoaHostCapabilities, type LoaRunState, type RuntimeSnapshot, type JsonValue, type LoaRoleId, type WorkerDispatchReceipt } from '../src/types.ts';
import { assembleWorkerBundle, coreBlindPolicyReference, verifyWorkerBundle } from '../src/worker-bundle.ts';
import { validateWorkerReturn, type ValidatedWorkerReturn } from '../src/worker-return.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const FAMILY = join(ROOT, 'docs/fixtures/formal-layout-bindings');
const TEMP = mkdtempSync(join(tmpdir(), 'aleph-material-process-'));
const OUTPUT = join(ROOT, '.aleph-bundles', `material-process-${process.pid}`);
const FIXED_TIME = '2026-09-11T12:00:00.000Z';
const clock = { now: () => FIXED_TIME };
let serial = 0;
const cases: string[] = [];
function pass(name: string): void { cases.push(name); console.log(`PASS ${name}`); }
function writable(root: string): void {
  chmodSync(root, 0o700);
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) writable(path); else chmodSync(path, 0o600);
  }
}
function initialState(
  runId: string,
  bundle: ReturnType<typeof verifyAndLoadLoaBundle>,
  profile: LoadedLoaProfile,
  host: LoaHostCapabilities,
  runtime: RuntimeSnapshot,
): LoaRunState {
  const models = Object.fromEntries(
    LOA_ROLE_IDS.map((role) => [
      role,
      structuredClone(host.models[profile.value.role_mappings[role].model_slot]),
    ]),
  ) as LoaRunState['identity']['models'];
  return {
    format: LOA_RUN_STATE_FORMAT,
    run_id: runId,
    mode: 'agent',
    full_mode: 'fixture-simulated',
    identity: {
      core: bundle.lock.core,
      adapter: bundle.lock.adapter,
      bundle: {
        ...bundle.lock.bundle,
        lock_digest: bundle.lock.lock_digest,
        lock_ref: 'control/original-bundle.lock.json',
        installation_ref: 'fixture-simulated',
      },
      checker_digest: bundle.lock.checker_digest,
      adapter_protocol_version: bundle.lock.adapter_protocol_version,
      run_format_version: bundle.lock.run_format_version,
      host: {
        ...host.host,
      },
      profile: {
        id: profile.value.id,
        digest: profile.digest,
      },
      models,
      runtime: {
        snapshot_ref: 'control/runtime/snapshot.json',
        digest: runtime.tree_digest,
      },
    },
    corpus: {
      state: 'frozen',
      inventory_ref: 'corpus/manifest.md',
      tree_digest: `sha256:${'9'.repeat(64)}`,
    },
    execution: {
      core_state: 'DISTILLING',
      stage: 'S4',
      stage_status: 'running',
      gate: null,
      halt: null,
      resume: {
        sequence: '0',
        checkpoint_digest: '',
        last_verified_at: FIXED_TIME,
      },
    },
    ledger: {
      writer_id: 'loa-orchestrator',
      sequence: '0',
      chain_head: sha256Digest(Buffer.alloc(0)),
    },
  };
}


try {
  // Exercise the unchanged 1.6 contract in an isolated synthetic compatibility
  // bundle. The retained 1.6 run fixture itself is never migrated.
  const assembled = assembleBundles(predecessorSource(ROOT, TEMP, '1.6.0-provisional'), OUTPUT);
  assert.equal(assembled.result, 'PASS', assembled.errors.join('; '));
  const bundle = verifyAndLoadLoaBundle(join(OUTPUT, 'aleph-for-loa'));
  const profile = loadLoaProfile(defaultProfilePath(bundle.root));
  const oldProfile = JSON.parse(readFileSync(defaultProfilePath(bundle.root), 'utf8'));
  delete oldProfile.role_mappings['verifier-l2f'];
  assert.throws(() => parseLoaProfile(oldProfile), /every Core role/u);
  assert(!('verifier-l2f' in parseLoaProfile(oldProfile, '1.5.0-provisional').role_mappings));
  pass('retained pre-1.6 profile may omit L2F while current profiles require it');
  const host = validateResolvedHost(readJsonFile(join(ROOT, 'adapters/loa/tests/fixtures/host-capabilities.json')), profile.value, { allowSimulation: true });
  function setup(): string {
    const run = join(TEMP, `run-${++serial}`);
    cpSync(join(FAMILY, 'positive'), run, { recursive: true });
    const log = readFileSync(join(run, 'run-log.md'), 'utf8');
    const c1 = log.indexOf('## 2026-08-14 09:00 UTC');
    assert(c1 > 0);
    writeFileSync(join(run, 'run-log.md'), log.slice(0, c1) + '## 2026-09-11 12:00 UTC — S4 — entry\n\nBounded fixture material use.\n');
    const manifest = join(run, 'run-manifest.md');
    writeFileSync(manifest, readFileSync(manifest, 'utf8').replace(/^.*\| ASSEMBLED \|.*\n/gmu, ''));
    const context = readRepresentationContext(loadRun(run));
    const source = context.carriers.get('SRC-401')!.bytes;
    const span = mdLineSpan(join(run, 'corpus/sources/SRC-401-source-walk.txt'), 3, 3)!;
    const bytes = source.subarray(span.startByte!, span.endByte!);
    context.inventory.bindings.push({ binding_id: 'BND-0900', representation_id: 'REP-0001', carrier_id: 'SRC-401', start_byte: String(span.startByte), end_byte: String(span.endByte), page_id: 'none', region_id: 'none', byte_role: 'frozen-source-bytes', fragment_hash: materialHash(bytes), exact_bytes_base64: bytes.toString('base64') });
    const exportBytes = Buffer.from('Synthetic supplied formal declaration.');
    mkdirSync(join(run, 'corpus/representation-assets'), { recursive: true });
    writeFileSync(join(run, 'corpus/representation-assets/AST-0900.txt'), exportBytes);
    context.inventory.assets.push({ asset_id: 'AST-0900', representation_id: 'REP-0001', role: 'structure-export', locus: 'corpus/representation-assets/AST-0900.txt', media_type: 'text/plain', encoding: 'utf8', byte_length: String(exportBytes.length), content_hash: materialHash(exportBytes) });
    context.inventory.provenance.push({ provenance_id: 'RPR-0900', representation_id: 'REP-0001', type: 'supplied-structure', actor: 'synthetic-export', tool: 'unknown', tool_version: 'unknown', input_refs: '["SRC-401"]', output_refs: '["AST-0900"]', parameters_asset_id: 'none', declaration_asset_id: 'AST-0900' });
    context.inventory.objects.push({ object_id: 'OBJ-0900', representation_id: 'REP-0001', kind: 'formal', parent_id: 'OBJ-0001', state: 'available', reason: 'none', provenance_id: 'RPR-0900', binding_ids: '["BND-0900"]', content_hash: materialFragmentsHash([bytes]), coordinates: '{"notation":"source-markup","structure_ids":[],"structure_state":"available"}' });
    context.inventory.associations.push({ association_id: 'ASC-0900', representation_id: 'REP-0001', kind: 'caption-for', subject_id: 'OBJ-0900', target_ids: '[]', state: 'unsupported', reason: 'No supplied caption.', provenance_id: 'RPR-0900' });
    const inventory = representationMarkdown(context.inventory);
    writeFileSync(join(run, 'corpus/representations.md'), inventory);
    writeFileSync(manifest, readFileSync(manifest, 'utf8').replace(/representation_inventory_hash: sha256:[0-9a-f]{64}/u, `representation_inventory_hash: ${materialHash(inventory)}`));
    const current = readRepresentationContext(loadRun(run));
    for (const use of current.uses) use.review_subject_digest = representationUseDigest(loadRun(run), current, use);
    writeFileSync(join(run, 'ledgers/representation-uses.md'), representationUsesMarkdown(current.uses));
    mkdirSync(join(run, 'control/runtime'), { recursive: true });
    const runtime = captureRuntimeSnapshot({ runId: 'RUN-typed-relations', bundle, profile, host, capturedAt: FIXED_TIME, outputPath: join(run, 'control/runtime/snapshot.json') });
    const state = initialState('RUN-typed-relations', bundle, profile, host, runtime);
    writeRunState(run, state);
    validateRepresentationRun(loadRun(run));
    return run;
  }
  function worker(run: string, role: LoaRoleId, raw: JsonValue, allowlist: string[] = [], inherited = false) {
    const state = readRunState(run), callId = `CALL-MATERIAL-${++serial}`;
    const coreRef = coreBlindPolicyReference(bundle, role, 'S4');
    const reviewId = allowlist[0]?.match(/([0-9a-f]{64})\.json$/u)?.[1]
      || (role === 'verifier-l2f' ? readdirSync(join(run, 'control/transactions')).find((n) => n.startsWith('RES-material-'))?.match(/([0-9a-f]{64})\.json$/u)?.[1] : undefined);
    const producerContext = role === 'verifier-l2f' && reviewId
      ? JSON.parse(readFileSync(join(run, 'control/transactions', `RES-material-${reviewId}.json`), 'utf8')).producer_context_id : null;
    const withheld = walkRegularFiles(run).map((p) => relative(run, p)).filter((p) => !p.startsWith('control/') && !allowlist.includes(p)).map((selector) => ({ selector, core_ref: coreRef }));
    const request = assembleWorkerBundle({ bundle, runDir: run, runId: state.run_id, stage: 'S4', callId, role,
      kind: role === 'verifier-l2f' ? 'refuter' : 'producer', allowlist, withheld,
      taskLine: role === 'verifier-l2f' ? 'Challenge the exact retained representation-use subject.' : 'Return this bounded synthetic proposal.',
      modelIdentity: state.identity.models[role], producerContextId: producerContext });
    const receipt: WorkerDispatchReceipt = { format: 'aleph-loa-worker-dispatch/v1', call_id: callId,
      context_id: inherited ? producerContext : `CTX-${callId}`, producer_context_id: request.request.isolation.producer_context_id,
      fresh_context: true, inherited_context: false, filesystem: 'bundle-read-only', model_identity: request.request.model_identity, simulation: { kind: 'fixture-simulated' } };
    const result = validateWorkerReturn({ workerBundleRoot: request.root, raw, dispatchReceipt: receipt });
    return { ...result, request };
  }
  const input = { requirements: [{ object_id: 'OBJ-0900', feature: 'formal-structure', binding_ids: ['BND-0900'] }], use_state: 'usable', fidelity_claim: 'none', limitation_refs: [], reason: 'none' };
  const producer: JsonValue = { canonicalizations: [{ lineage_type: 'merge', predecessors: ['CC-0404'], successor: { normalized_claim: 'Retained formal bytes.', packets: ['PKT-0401'], claim_type: 'factual', material_use: input }, basis: 'synthetic', corroboration: 'restatement', rationale: 'WITHHELD-PRODUCER-RATIONALE.', flags: [] }], contradiction_pairs: [], material_findings: [] };
  const verdict: JsonValue = { verdict: 'upheld', rationale: 'Fixture-simulated attack only.', attacks_tried: ['glyph loss'], evidence_ids: ['PKT-0401'], candidate_evidence: [], missing_for_determination: null, flags: [] };
  function proposal(run: string): { row: MaterialRow; render: () => Record<string, string> } {
    const row: MaterialRow = { use_id: 'USE-0900', owner_stage: 'S4', subject_kind: 'CC', subject_id: 'CC-0900', basis_packet_ids: '["PKT-0401"]', requirements: JSON.stringify(input.requirements), use_state: 'usable', fidelity_claim: 'none', limitation_refs: '[]', reason: 'none', established_by: 'invocation:fixture-material', review_subject_digest: '', reviewed_by: 'none' };
    const text = readFileSync(join(run, 'ledgers/claim-inventory.md'), 'utf8') + '| CC-0900 | Retained formal bytes. | PKT-0401 | SRC-401 | factual | | | | | active |\n';
    return { row, render: () => ({ 'ledgers/claim-inventory.md': text }) };
  }
  const run = setup(), writer = new LedgerWriter(run, clock);
  const accepted = worker(run, 'merge-judge', producer);
  assert.equal(accepted.report.result, 'PASS', accepted.report.errors.join('; '));
  const validated = accepted.validated!;
  const proposed = proposal(run);
  const before = readFileSync(join(run, 'ledgers/claim-inventory.md'));
  const reserved = writer.reserveMaterialUse(validated, proposed.row, proposed.render);
  assert(readFileSync(join(run, 'ledgers/claim-inventory.md')).equals(before));
  assert.equal(loadRun(run).claims.some((c) => c.values.claimId === 'CC-0900'), false);
  pass('reservation retains exact subject ID without writing a claim');
  assert.deepEqual(writer.reserveMaterialUse(validated, proposed.row, proposed.render), reserved);
  pass('identical reservation retry reuses subject identity');
  assert.throws(() => writer.reserveMaterialUse(validated, { ...reserved.row, fidelity_claim: 'exact-representation' }, proposed.render),
    /FIDELITY|subject|producer|requirements/u);
  assert(readFileSync(join(run, 'ledgers/claim-inventory.md')).equals(before));
  pass('reused reservation with changed material requirements refuses before writing');
  const reviewed = worker(run, 'verifier-l2f', verdict, [reserved.review_path]);
  assert.equal(reviewed.report.result, 'PASS', reviewed.report.errors.join('; '));
  verifyWorkerBundle(reviewed.request.root);
  const view = readFileSync(join(run, reserved.review_path), 'utf8');
  assert(!view.includes('WITHHELD-PRODUCER-RATIONALE') && !view.includes('disposition'));
  const materialView = JSON.parse(view);
  assert(materialView.provenance.some((p: MaterialRow) => p.type === 'capture'));
  assert(materialView.provenance.some((p: MaterialRow) => p.type === 'supplied-structure'));
  assert(materialView.assets.some((a: MaterialRow) => a.asset_id === 'AST-0900' && a.content_hash));
  assert(materialView.assets.every((a: MaterialRow) => a.asset_id !== 'AST-0900' || !a.bytes_base64));
  assert.equal(reviewed.request.request.allowlist.length, 1);
  pass('fresh L2F receives only exact subject, packet bytes and selected closure');
  assert.throws(() => worker(run, 'verifier-l2f', verdict, [reserved.review_path], true), /producer|context/u);
  assert.throws(() => worker(run, 'verifier-l2f', verdict, ['ledgers/claim-inventory.md']), /reserved Core material review/u);
  pass('producer context and full claim-ledger leakage refused before acceptance');
  const bad = worker(run, 'verifier-l2f', { ...(verdict as object), candidate_evidence: [{ start_byte: 0, end_byte: 1, source_locator: 'L3-L3', exact_bytes_base64: 'YQ==' }] }, [reserved.review_path]);
  assert.equal(bad.report.result, 'FAIL');
  pass('L2F cannot author extraction candidates');
  writer.append('verification/harness/VER-0900.md', reviewed.validated!, () => '# Verdict VER-0900\n\n| field | value |\n| --- | --- |\n| lens | L2F |\n| stage | S4 |\n| target | representation-use-subject:' + reserved.row.review_subject_digest + ' |\n| shown | exact reserved material view |\n| withheld | producer rationale and other batches |\n| verdict | upheld |\n| consequence | identical usable subject only; fixture simulation |\n');
  const row = { ...reserved.row, reviewed_by: 'VER-0900' };
  assert.throws(() => writer.appendMaterialUse(validated, row, proposed.render), /accepted fresh L2F/u);
  pass('static VER alone cannot satisfy host fresh transport obligation');
  const refused = worker(run, 'verifier-l2f', { ...(verdict as object), verdict: 'cannot-determine', missing_for_determination: 'transport cannot consume modality' }, [reserved.review_path]);
  assert.throws(() => writer.appendMaterialUse(validated, row, proposed.render, refused.validated!), /USE_CLOSURE/u);
  pass('cannot-determine review cannot authorize affirmative use');
  const stateBefore = readFileSync(join(run, 'control/run-state.json'));
  const usesBefore = readFileSync(join(run, 'ledgers/representation-uses.md'));
  const chainBefore = existsSync(join(run, 'control/ledger-chain.jsonl')) ? readFileSync(join(run, 'control/ledger-chain.jsonl')) : Buffer.alloc(0);
  writer.appendMaterialUse(validated, row, proposed.render, reviewed.validated!);
  validateRepresentationRun(loadRun(run));
  assert.equal(loadRun(run).claims.filter((c) => c.values.claimId === 'CC-0900').length, 1);
  const usesAfter = readFileSync(join(run, 'ledgers/representation-uses.md'));
  writer.appendMaterialUse(validated, row, proposed.render, reviewed.validated!);
  assert(readFileSync(join(run, 'ledgers/representation-uses.md')).equals(usesAfter));
  pass('reviewed subject and receipt commit once; duplicate return is byte-idempotent');
  const transactionPath = readdirSync(join(run, 'control/transactions')).find((n) => n.startsWith('TXN-material-'))!;
  const transaction = JSON.parse(readFileSync(join(run, 'control/transactions', transactionPath), 'utf8'));
  for (const partial of ['none', 'subject', 'uses', 'chain', 'state']) {
    const copy = join(TEMP, `recovery-${partial}`); cpSync(run, copy, { recursive: true }); writable(copy);
    writeFileSync(join(copy, 'control/transactions', transactionPath), stableJsonBytes({ ...transaction, status: 'prepared' }));
    if (partial === 'none') writeFileSync(join(copy, 'ledgers/claim-inventory.md'), before);
    if (['none', 'subject'].includes(partial)) writeFileSync(join(copy, 'ledgers/representation-uses.md'), usesBefore);
    if (['none', 'subject', 'uses'].includes(partial)) writeFileSync(join(copy, 'control/ledger-chain.jsonl'), chainBefore);
    if (partial !== 'state') writeFileSync(join(copy, 'control/run-state.json'), stateBefore);
    const processResult = spawnSync(process.execPath, ['--input-type=module', '-e', 'const [m,r]=process.argv.slice(1); const x=await import(m); x.recoverPendingMaterialTransactions(r);', new URL('../src/ledger-writer.ts', import.meta.url).href, copy], { encoding: 'utf8' });
    assert.equal(processResult.status, 0, processResult.stderr);
    assert(readFileSync(join(copy, 'ledgers/representation-uses.md')).equals(usesAfter));
    recoverPendingMaterialTransactions(copy);
  }
  pass('fresh process recovers every subject/use/chain/state interruption from exact prepared bytes');
  const tamper = join(TEMP, 'tampered'); cpSync(run, tamper, { recursive: true }); writable(tamper);
  writeFileSync(join(tamper, 'control/transactions', transactionPath), stableJsonBytes({ ...transaction, status: 'prepared' }));
  writeFileSync(join(tamper, 'ledgers/representation-uses.md'), 'changed preimage');
  assert.throws(() => recoverPendingMaterialTransactions(tamper), /preimage/u);
  pass('changed transaction preimage refuses replay');
  const findingReturn = worker(run, 'merge-judge', {
    canonicalizations: [], contradiction_pairs: [],
    material_findings: [{ object_id: 'OBJ-0900', material_use: {
      requirements: [{ object_id: 'OBJ-0900', feature: 'chart-values', binding_ids: [] }],
      use_state: 'CANNOT_DETERMINE', fidelity_claim: 'none', limitation_refs: ['ASC-0900'],
      reason: 'No supplied chart values are present.',
    } }],
  });
  assert.equal(findingReturn.report.result, 'PASS', findingReturn.report.errors.join('; '));
  const claimCount = loadRun(run).claims.length;
  writer.appendMaterialFindings(findingReturn.validated!);
  writer.appendMaterialFindings(findingReturn.validated!);
  const findings = readRepresentationContext(loadRun(run)).uses.filter((u) => u.use_state === 'CANNOT_DETERMINE');
  assert.equal(findings.length, 1); assert.equal(loadRun(run).claims.length, claimCount);
  pass('failed material candidates persist once as OBJ receipts without manufacturing a claim');
  const closureRun = setup(), closureWriter = new LedgerWriter(closureRun, clock);
  const closureState = readFileSync(join(closureRun, 'control/run-state.json'));
  const closureLog = readFileSync(join(closureRun, 'run-log.md'));
  closureWriter.advanceSlice5ClosurePhase('S4-C1-relations-closed');
  const closedLog = readFileSync(join(closureRun, 'run-log.md'));
  const closureTxnName = readdirSync(join(closureRun, 'control/transactions')).find((n) => n.startsWith('TXN-material-'))!;
  const closureTxn = JSON.parse(readFileSync(join(closureRun, 'control/transactions', closureTxnName), 'utf8'));
  writeFileSync(join(closureRun, 'run-log.md'), closureLog);
  writeFileSync(join(closureRun, 'control/run-state.json'), closureState);
  writeFileSync(join(closureRun, 'control/transactions', closureTxnName), stableJsonBytes({ ...closureTxn, status: 'prepared' }));
  recoverPendingMaterialTransactions(closureRun);
  assert(readFileSync(join(closureRun, 'run-log.md')).equals(closedLog));
  validateRepresentationRun(loadRun(closureRun));
  pass('prepared C1 journal restores its original marker and exact use seal');
  const late = worker(closureRun, 'merge-judge', producer);
  const lateProposal = proposal(closureRun);
  assert.throws(() => closureWriter.reserveMaterialUse(late.validated!, lateProposal.row, lateProposal.render), /FROZEN_WRITE/u);
  assert(readRunState(closureRun).execution.halt);
  pass('post-C1 material arrival refuses new use and retains a durable halt');
  // Capture through the actual public start/freeze path, without a model invocation.
  const loaRoot = join(TEMP, 'loa'); mkdirSync(loaRoot);
  const inputsRoot = join(loaRoot, 'fixture-inputs'); cpSync(join(FAMILY, 'inputs'), inputsRoot, { recursive: true });
  const capabilitiesPath = join(TEMP, 'capabilities.json'); cpSync(join(ROOT, 'adapters/loa/tests/fixtures/host-capabilities.json'), capabilitiesPath);
  const started = startLoaRun([join(inputsRoot, 'table.aleph-representation.json')], { loaRoot, bundleRoot: bundle.root, capabilitiesPath, allowSimulation: true, clock, idSource: { nextRunId: () => 'RUN-material-capture', nextCallId: () => 'CALL-capture' } });
  assert.equal(started.result, 'BLOCKED', started.errors.join('; '));
  const captureRun = join(loaRoot, 'grimoires/loa/aleph/runs/RUN-material-capture');
  assert(!existsSync(join(captureRun, 'corpus/representations.md')));
  const corpus = verifyCorpusSnapshot(captureRun);
  const beforeFreezeState = readFileSync(join(captureRun, 'control/run-state.json'));
  const beforeFreezeSnapshot = readFileSync(join(captureRun, 'control/corpus.snapshot.json'));
  const beforeFreezeFiles = Object.fromEntries(['run-manifest.md', 'run-log.md', 'corpus/manifest.md'].map((p) => [p, readFileSync(join(captureRun, p))]));
  const frozen = recordS0AuthorityResponse(corpus.run_id, { format: 'aleph-loa-authority-response/v1', gate_id: 'S0', run_id: corpus.run_id, authority: { kind: 'human', identity: 'fixture-simulated-human' }, decision: 'approve-freeze', declared_scope: 'Bounded synthetic representation fixture.', exclusions: [], sensitivity_rulings: corpus.files.map((f) => ({ source_id: f.source_id, labels: ['none'], decision: 'admit-exact-bytes' })), freeze: true, recorded_at: FIXED_TIME, simulation: { kind: 'fixture-simulated' } }, { loaRoot, allowSimulation: true, clock });
  assert.equal(frozen.result, 'PASS', frozen.errors.join('; '));
  validateRepresentationRun(loadRun(captureRun));
  pass('public start retains descriptor and ID map; S0 freezes only authorized canonical inventory');
  const freezeJournalPath = join(captureRun, 'control/transactions/TXN-s0-freeze.json');
  const freezeJournal = JSON.parse(readFileSync(freezeJournalPath, 'utf8'));
  delete freezeJournal.committed_at; freezeJournal.status = 'prepared';
  const captureAsset = readRepresentationContext(loadRun(captureRun)).inventory.assets[0];
  for (const phase of ['partial-assets', 'complete-bytes-no-ack']) {
    writeFileSync(join(captureRun, 'control/run-state.json'), beforeFreezeState);
    if (phase === 'partial-assets') {
      writeFileSync(join(captureRun, 'control/corpus.snapshot.json'), beforeFreezeSnapshot);
      for (const [path, bytes] of Object.entries(beforeFreezeFiles)) writeFileSync(join(captureRun, path), bytes);
      rmSync(join(captureRun, captureAsset.locus));
    }
    writeFileSync(freezeJournalPath, stableJsonBytes(freezeJournal));
    const recovered = resumeLoaRun(corpus.run_id, { loaRoot, allowSimulation: true, clock });
    assert.equal(recovered.result, 'PASS', recovered.errors.join('; '));
    assert.equal(readRunState(captureRun).corpus.state, 'frozen');
    validateRepresentationRun(loadRun(captureRun));
  }
  pass('prepared imported capture recovers missing asset and absent freeze acknowledgement from exact journal bytes');
  function intake(inputs: string[]) {
    const destination = join(TEMP, `intake-${++serial}`);
    mkdirSync(destination);
    return snapshotCorpus({ loaRoot: TEMP, runDir: destination, runId: `RUN-intake-${serial}`, inputs, capturedAt: FIXED_TIME, formalLayout: true });
  }
  assert.throws(() => intake([join(inputsRoot, 'table.aleph-representation.json'), join(inputsRoot, 'material.txt')]), /selected more than once/u);
  const malformed = join(inputsRoot, 'bad.aleph-representation.json'); writeFileSync(malformed, '{"format":"unknown"}');
  assert.throws(() => intake([malformed]), /FORMAT/u);
  const ordinary = join(inputsRoot, 'ordinary.json'); writeFileSync(ordinary, '{"format":"unknown"}');
  assert.equal(intake([ordinary]).files.length, 1);
  const traversal = JSON.parse(readFileSync(join(inputsRoot, 'table.aleph-representation.json'), 'utf8'));
  traversal.source_path = '../outside.txt'; writeFileSync(malformed, JSON.stringify(traversal));
  assert.throws(() => intake([malformed]), /CAPTURE_HASH/u);
  pass('explicit input closure refuses duplicate members, malformed reserved descriptors and traversal; ordinary JSON remains text');
  const opaqueBytes = readFileSync(join(inputsRoot, 'opaque.bin'));
  const opaque = JSON.parse(readFileSync(join(inputsRoot, 'table.aleph-representation.json'), 'utf8'));
  opaque.source_path = 'opaque.bin'; opaque.extraction_surface = 'opaque'; opaque.state = 'unsupported'; opaque.reason = 'No textual extraction surface.';
  opaque.assets = []; opaque.objects = [opaque.objects[0]]; opaque.associations = [];
  opaque.objects[0].content_hash = materialFragmentsHash([opaqueBytes]);
  opaque.bindings = [{ binding_id: 'BND-0001', carrier_id: 'source', start_byte: '0', end_byte: String(opaqueBytes.length), page_id: 'none', region_id: 'none',
    byte_role: 'frozen-source-bytes', fragment_hash: materialHash(opaqueBytes), exact_bytes_base64: opaqueBytes.toString('base64') }];
  const opaquePath = join(inputsRoot, 'opaque.aleph-representation.json'); writeFileSync(opaquePath, JSON.stringify(opaque));
  const opaqueStarted = startLoaRun([opaquePath], { loaRoot, bundleRoot: bundle.root, capabilitiesPath, allowSimulation: true, clock, idSource: { nextRunId: () => 'RUN-material-opaque', nextCallId: () => 'CALL-opaque' } });
  assert.equal(opaqueStarted.result, 'BLOCKED', opaqueStarted.errors.join('; '));
  const opaqueRun = join(loaRoot, 'grimoires/loa/aleph/runs/RUN-material-opaque'), opaqueCorpus = verifyCorpusSnapshot(opaqueRun);
  const opaqueFrozen = recordS0AuthorityResponse(opaqueCorpus.run_id, { format: 'aleph-loa-authority-response/v1', gate_id: 'S0', run_id: opaqueCorpus.run_id,
    authority: { kind: 'human', identity: 'fixture-simulated-human' }, decision: 'approve-freeze', declared_scope: 'Retain unsupported synthetic capture honestly.',
    exclusions: [], sensitivity_rulings: opaqueCorpus.files.map((f) => ({ source_id: f.source_id, labels: ['none'], decision: 'admit-exact-bytes' })),
    freeze: true, recorded_at: FIXED_TIME, simulation: { kind: 'fixture-simulated' } }, { loaRoot, allowSimulation: true, clock });
  assert.equal(opaqueFrozen.result, 'PASS', opaqueFrozen.errors.join('; '));
  for (let retry = 0; retry < 2; retry++) {
    const blocked = resumeLoaRun(opaqueCorpus.run_id, { loaRoot, allowSimulation: true, clock });
    assert.notEqual(blocked.result, 'PASS');
    assert(blocked.errors.some((e) => e.includes('UNSUPPORTED_EXTRACTION_SURFACE')));
    assert(readRunState(opaqueRun).execution.halt);
    assert.equal(loadRun(opaqueRun).packets.length, 0);
  }
  pass('opaque public capture stays durably blocked across repeated resume without packets');
  const asset = readRepresentationContext(loadRun(captureRun)).inventory.assets[0];
  chmodSync(join(captureRun, asset.locus), 0o600); writeFileSync(join(captureRun, asset.locus), 'tamper');
  const resumed = resumeLoaRun('RUN-material-capture', { loaRoot, allowSimulation: true, clock });
  assert.notEqual(resumed.result, 'PASS');
  assert(readRunState(captureRun).execution.halt);
  pass('changed frozen asset halts resumed execution durably');
  console.log(`REAL MODEL CALLS: none\nRESULT: PASS (${cases.length}/${cases.length})`);
} finally {
  writable(TEMP); rmSync(TEMP, { recursive: true, force: true });
  if (existsSync(OUTPUT)) { writable(OUTPUT); rmSync(OUTPUT, { recursive: true, force: true }); }
}
