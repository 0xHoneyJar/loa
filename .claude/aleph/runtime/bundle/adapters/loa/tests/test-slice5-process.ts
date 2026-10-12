#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import {
  chmodSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { predecessorSource } from '../../../scripts/compatibility-fixture-source.ts';
import { assembleBundles } from '../../../scripts/assemble-bundles.ts';
import {
  buildProceduralAuthorityRequest,
  buildProceduralAuthorityResponse,
  buildProceduralAuthoritySubject,
  exactTextBlob,
  materialImpactSubjectDigest,
  materialImpactSubjectJson,
  proceduralAuthorityRequestJson,
  resolvePinnedCoreRequirement,
  restrictionOverlay,
  type MaterialImpactSubject,
  type PinnedCoreAuthority,
  type ProceduralAction,
} from '../../../scripts/lib/internal-ambiguity.ts';
import {
  firstRunLogEntry,
  hasRunLogEvent,
} from '../../../scripts/lib/check-helpers.ts';
import { runK2Ambiguities } from '../../../scripts/lib/checks-k2-ambiguities.ts';
import { ResultCollector } from '../../../scripts/lib/results.ts';
import { loadRun } from '../../../scripts/lib/run-model.ts';
import {
  readVerifiedBundleLock,
  verifyAndLoadLoaBundle,
} from '../src/core-loader.ts';
import {
  recordS0AuthorityResponse,
  startLoaRun,
} from '../src/cli.ts';
import {
  digestTreeRecords,
  readJsonFile,
  sha256Digest,
  stableJsonBytes,
  walkRegularFiles,
  writeJsonAtomic,
} from '../src/fs.ts';
import { verifyCorpusSnapshot } from '../src/intake.ts';
import {
  LedgerWriter,
  recoverPendingLedgerTransactions,
} from '../src/ledger-writer.ts';
import {
  openHumanAuthorityGate,
  readRunState,
  recordHumanAuthorityDecision,
  recoverPendingAuthorityTransactions,
  writeRunState,
} from '../src/run-control.ts';
import {
  captureRuntimeSnapshot,
  defaultProfilePath,
  loadLoaProfile,
  validateResolvedHost,
  type LoadedLoaProfile,
} from '../src/runtime-snapshot.ts';
import {
  LOA_ROLE_IDS,
  LOA_RUN_STATE_FORMAT,
  type Clock,
  type IdSource,
  type JsonValue,
  type LoaHostCapabilities,
  type LoaRoleId,
  type LoaRunState,
  type RuntimeSnapshot,
  type S0AuthorityResponse,
  type WorkerDispatchReceipt,
} from '../src/types.ts';
import {
  assembleWorkerBundle,
  coreBlindPolicyReference,
  verifyWorkerBundle,
} from '../src/worker-bundle.ts';
import { acceptLoaWorkerHandoff } from '../src/worker-dispatch.ts';
import {
  validateWorkerReturn,
  type ValidatedWorkerReturn,
} from '../src/worker-return.ts';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const FIXTURE_ROOT = join(REPO_ROOT, 'docs/fixtures/internal-ambiguity-lifecycle');
const HOST_CAPABILITIES_FIXTURE = join(
  REPO_ROOT,
  'adapters/loa/tests/fixtures/host-capabilities.json',
);
const FIXED_TIME = '2040-01-02T03:10:00.000Z';
const CLOCK: Clock = { now: () => FIXED_TIME };
const S0_START_CLOCK: Clock = { now: () => '2026-08-14T08:00:00.000Z' };
const S0_RESPONSE_CLOCK: Clock = { now: () => '2026-08-14T08:05:00.000Z' };
const CASES: string[] = [];

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function expectThrows(operation: () => unknown, pattern: RegExp, label: string): void {
  let thrown: unknown;
  try {
    operation();
  } catch (error) {
    thrown = error;
  }
  expect(thrown !== undefined, `${label} unexpectedly succeeded`);
  const message = thrown instanceof Error ? thrown.message : String(thrown);
  expect(pattern.test(message), `${label} failed with unexpected diagnostic: ${message}`);
}

function pass(name: string): void {
  CASES.push(name);
  console.log(`PASS ${name}`);
}

function runJsonProcess(script: string, args: string[]): Record<string, JsonValue> {
  const result = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  if (result.error || result.status !== 0) {
    let diagnostic = result.stderr || result.stdout;
    try {
      const parsed = JSON.parse(result.stdout) as {
        details?: { kernel_report?: string };
      };
      const reportPath = parsed.details?.kernel_report;
      if (reportPath && existsSync(reportPath)) {
        diagnostic += `\n${readFileSync(reportPath, 'utf8')}`;
      }
    } catch {
      // Preserve the process diagnostic when stdout is not JSON.
    }
    throw new Error(
      `process failed: ${result.error ? String(result.error) : diagnostic}`,
    );
  }
  return JSON.parse(result.stdout) as Record<string, JsonValue>;
}

function runFailingJsonProcess(script: string, args: string[]): Record<string, JsonValue> {
  const result = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  if (result.error || result.status === 0) {
    throw new Error(
      `process unexpectedly passed: ${
        result.error ? String(result.error) : result.stderr || result.stdout
      }`,
    );
  }
  return JSON.parse(result.stdout) as Record<string, JsonValue>;
}

function enterS5InShippedRuntime(bundleRoot: string, run: string): void {
  const result = spawnSync(process.execPath, [
    '--input-type=module',
    '-e',
    `
      import { pathToFileURL } from 'node:url';
      const [script, run, time] = process.argv.slice(1);
      const { LedgerWriter } = await import(pathToFileURL(script).href);
      new LedgerWriter(run, { now: () => time }).enterS5AfterSlice5Closure();
    `,
    join(bundleRoot, 'runtime-js/adapters/loa/src/ledger-writer.js'),
    run,
    FIXED_TIME,
  ], { encoding: 'utf8' });
  expect(!result.error && result.status === 0,
    `shipped S5 transition failed: ${result.error || result.stderr}`);
}

function runFixtureDispatchProcess(
  runtimeScript: string,
  workerBundleRoot: string,
  returnRoot: string,
  rawPath: string,
  contextId: string,
): void {
  const source = `
    import { readFileSync } from 'node:fs';
    import { pathToFileURL } from 'node:url';
    const [runtimeScript, workerBundleRoot, returnRoot, rawPath, contextId] = process.argv.slice(1);
    process.argv[1] = 'fixture-dispatch-harness';
    const runtime = await import(pathToFileURL(runtimeScript).href);
    const request = JSON.parse(readFileSync(workerBundleRoot + '/request.json', 'utf8'));
    const structuredReturn = JSON.parse(readFileSync(rawPath, 'utf8'));
    runtime.dispatchPreparedLoaWorker({
      workerBundleRoot,
      returnRoot,
      host: {
        invokeFreshContext() {
          return {
            receipt: {
              format: 'aleph-loa-worker-dispatch/v1',
              call_id: request.call_id,
              context_id: contextId,
              producer_context_id: request.isolation.producer_context_id,
              fresh_context: true,
              inherited_context: false,
              filesystem: 'bundle-read-only',
              model_identity: request.model_identity,
              simulation: { kind: 'fixture-simulated' }
            },
            structured_return: structuredReturn
          };
        }
      }
    });
  `;
  const result = spawnSync(
    process.execPath,
    [
      '--input-type=module',
      '--eval',
      source,
      runtimeScript,
      workerBundleRoot,
      returnRoot,
      rawPath,
      contextId,
    ],
    { encoding: 'utf8' },
  );
  if (result.error || result.status !== 0) {
    throw new Error(
      `fixture dispatch process failed: ${
        result.error ? String(result.error) : result.stderr || result.stdout
      }`,
    );
  }
}

function fixtureS0Response(
  corpus: ReturnType<typeof verifyCorpusSnapshot>,
): S0AuthorityResponse {
  return {
    format: 'aleph-loa-authority-response/v1',
    gate_id: 'S0',
    run_id: corpus.run_id,
    authority: {
      kind: 'human',
      identity: 'fixture-simulated-human-authority',
    },
    decision: 'approve-freeze',
    declared_scope: 'Fixture-simulated exact S0 source intake for Slice 5 coexistence.',
    exclusions: [],
    sensitivity_rulings: corpus.files.map((file) => ({
      source_id: file.source_id,
      labels: ['none'],
      decision: 'admit-exact-bytes',
    })),
    freeze: true,
    recorded_at: S0_RESPONSE_CLOCK.now(),
    simulation: { kind: 'fixture-simulated' },
  };
}

function slice5WorkerReturn(role: LoaRoleId): JsonValue {
  if (role === 'ambiguity-producer') {
    return {
      definition: {
        source_entity_kind: 'CC',
        source_entity_id: 'CC-0413',
        source_id: 'SRC-0401',
        expression_locator: 'L8-L8',
        expression_start_byte: 277,
        expression_end_byte: 286,
        expression_sha256: 'sha256:dda18a0e21ae47c53b4309434cbc02ae8bf764fa83a6defbb719431242722aa7',
        expression_bytes_base64: 'Y2FuZGlkYXRl',
        basis_packet_ids: ['PKT-0405'],
        detected_by: 'invocation:ambiguity-producer-03',
      },
      assessment: {
        search_scope_kind: 'full-same-source',
        search_source_id: 'SRC-0401',
        search_completion_ref: 'SRC-0401@CUR-0406@sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984',
        search_basis_digest: 'sha256:580ad9aee5a5b3b060c0f734542e08956c097060b34d56dc672c54fc5c2f3a80',
        candidate_state: 'null-no-candidate',
        candidate_refs: [],
        affected_relation_ids: [],
        resolution_state: 'unresolved',
        carry_state: 'none',
        proposed_by: 'invocation:ambiguity-producer-03',
        review_subject_digest: 'sha256:971c8b4b48522d87dc994a48823f1f4eabce05cd1c990b1bd08f506e5caf201d',
      },
      flags: ['fixture-simulated'],
    };
  }
  if (role === 'ambiguity-reviewer') {
    return {
      target: 'internal-ambiguity-review-subject:sha256:971c8b4b48522d87dc994a48823f1f4eabce05cd1c990b1bd08f506e5caf201d',
      verdict: 'upheld',
      shown: 'exact fixture ambiguity subject and frozen basis',
      withheld: 'producer rationale and human procedural authority',
      consequence: 'fixture-simulated structural review only',
      flags: ['fixture-simulated'],
    };
  }
  if (role === 'material-impact-producer') {
    return {
      materiality_class: 'C',
      operative_scope: {
        affected_ids: ['CC-0413'],
        impact_rows: [{
          affected_id: 'CC-0413',
          operation_kind: 'required-barrier-dod',
          requirement_ref: 'core:docs/architecture/templates/09-internal-ambiguity.md#S4 composite barrier',
          unresolved_treatment: 'carry-or-restriction',
          consequence_if_unresolved: 'C2 retains the unresolved ambiguity without changing later semantic judgments.',
        }],
      },
      source_locators: ['SRC-0401:L8-L8'],
      reviewed_unaffected_ids: [],
      unresolved_statement: 'The frozen same-source bytes do not identify one local referent.',
      proposed_by: 'invocation:material-impact-producer-fixture',
      flags: ['fixture-simulated'],
    };
  }
  return {
    target: `internal-ambiguity-material-impact-review-subject:sha256:${'4'.repeat(64)}`,
    verdict: 'upheld',
    shown: 'exact fixture material-impact subject and retained Core basis',
    withheld: 'producer rationale and human procedural authority',
    consequence: 'fixture-simulated structural review only',
    flags: ['fixture-simulated'],
  };
}

function makeWritable(path: string): void {
  if (!existsSync(path)) return;
  const stat = lstatSync(path);
  if (stat.isDirectory()) {
    chmodSync(path, 0o700);
    for (const entry of readdirSync(path)) makeWritable(join(path, entry));
  } else {
    chmodSync(path, 0o600);
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

function preC1RunLog(finalLog: string): string {
  const boundary = '\n## 2026-08-14 09:00 UTC — S4 — C1\n';
  const index = finalLog.indexOf(boundary);
  expect(index >= 0, 'fixture run log omits the S4-C1 boundary');
  return `${finalLog.slice(0, index)}\n\n## 2026-08-14 08:55 UTC — S4 — entry\n\n`
    + 'Prepared the canonical relation ledger for the composite Slice 5 closure barrier.\n';
}

function emptyAmbiguityLedger(runId: string): string {
  return `# Internal Ambiguities — ${runId}\n\n`
    + '- internal_ambiguity_format: aleph-internal-ambiguity/v1\n\n'
    + '## T5.1 Ambiguity definitions\n\n'
    + '| ambiguity_id | source_entity_kind | source_entity_id | source_id | expression_locator | expression_start_byte | expression_end_byte | expression_sha256 | expression_bytes_base64 | basis_packet_ids | detected_by |\n'
    + '|--------------|--------------------|------------------|-----------|--------------------|-----------------------|---------------------|-------------------|-------------------------|------------------|-------------|\n\n'
    + '## T5.2 Reviewed assessments\n\n'
    + '| ambiguity_id | assessment_seq | predecessor_assessment_seq | search_scope_kind | search_source_id | search_completion_ref | search_basis_digest | candidate_state | candidate_refs | affected_relation_ids | resolution_state | carry_state | proposed_by | review_subject_digest | reviewed_by |\n'
    + '|--------------|----------------|----------------------------|-------------------|------------------|-----------------------|---------------------|-----------------|----------------|-----------------------|------------------|-------------|-------------|-----------------------|-------------|\n\n'
    + '## T5.3 Procedural authority\n\n'
    + '| ambiguity_id | authority_seq | assessment_seq | action | selected_candidate_ref | authority_subject_digest | authority_ref | closure_provenance |\n'
    + '|--------------|---------------|----------------|--------|------------------------|--------------------------|---------------|--------------------|\n';
}

function materialReviewText(
  verifierId: string,
  digest: string,
  verdict: 'upheld' | 'refuted' | 'cannot-determine',
  consequence: string,
): string {
  return `# Verdict ${verifierId}\n\n`
    + '| field | value |\n'
    + '|-------|-------|\n'
    + `| target | internal-ambiguity-material-impact-review-subject:${digest} |\n`
    + '| lens | fresh material-impact exact-subject challenge |\n'
    + '| stage | S4-C2 material-impact review |\n'
    + '| shown | exact material subject, bound T5.2 review, cited Core requirement, reopened object, and C1 basis |\n'
    + '| withheld | human comments, observations, forecasts, desired actions, candidate preferences, and desired conclusions |\n'
    + `| verdict | ${verdict} |\n`
    + `| consequence | ${consequence} |\n`;
}

function withheldInventory(
  bundle: ReturnType<typeof verifyAndLoadLoaBundle>,
  runDir: string,
  role: LoaRoleId,
  allowlist: string[],
  stage: 'S4' | 'S5' = 'S4',
) {
  const allowed = new Set(allowlist);
  const coreRef = coreBlindPolicyReference(bundle, role, stage);
  return walkRegularFiles(runDir)
    .map((path) => relative(runDir, path).split(sep).join('/'))
    .filter((path) => !path.startsWith('control/') && !allowed.has(path))
    .sort((left, right) => left.localeCompare(right))
    .map((selector) => ({ selector, core_ref: coreRef }));
}

function validatedFixtureReturn(
  bundle: ReturnType<typeof verifyAndLoadLoaBundle>,
  runDir: string,
  state: LoaRunState,
): ValidatedWorkerReturn<JsonValue> {
  const assembled = assembleWorkerBundle({
    bundle,
    runDir,
    callId: 'CALL-SLICE5-PROCESS-0001',
    runId: state.run_id,
    stage: 'S4',
    role: 'merge-judge',
    kind: 'producer',
    allowlist: [],
    withheld: withheldInventory(bundle, runDir, 'merge-judge', []),
    taskLine: 'Return the sealed fixture merge-judge exemplar.',
    modelIdentity: state.identity.models['merge-judge'],
  });
  const raw: JsonValue = {
    canonicalizations: [{
      lineage_type: 'merge',
      predecessors: ['CC-0401'],
      successor: {
        normalized_claim: 'Fixture-only canonical claim.',
        packets: ['PKT-0401'],
        claim_type: 'descriptive',
      },
      basis: 'Fixture-only validated return for writer process evidence.',
      corroboration: 'independent',
      rationale: 'Exercise the branded return boundary without semantic use.',
      flags: [],
    }],
    contradiction_pairs: [{
      a: 'CC-0401',
      b: 'CC-0402',
      why: 'Fixture-only structural pair.',
    }],
  };
  const receipt: WorkerDispatchReceipt = {
    format: 'aleph-loa-worker-dispatch/v1',
    call_id: assembled.request.call_id,
    context_id: 'CTX-SLICE5-PROCESS-0001',
    producer_context_id: null,
    fresh_context: true,
    inherited_context: false,
    filesystem: 'bundle-read-only',
    model_identity: assembled.request.model_identity,
    simulation: { kind: 'fixture-simulated' },
  };
  const result = validateWorkerReturn({
    workerBundleRoot: assembled.root,
    raw,
    dispatchReceipt: receipt,
  });
  expect(result.report.result === 'PASS' && result.validated !== null,
    `fixture worker return failed validation: ${result.report.errors.join('; ')}`);
  return result.validated as ValidatedWorkerReturn<JsonValue>;
}

function main(): void {
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-slice5-process-'));
  const bundleOutput = join(REPO_ROOT, '.aleph-bundles', `slice5-process-${process.pid}`);
  try {
    const assembly = assembleBundles(predecessorSource(REPO_ROOT, tempRoot), bundleOutput);
    expect(assembly.result === 'PASS', `temporary bundle assembly failed: ${assembly.errors.join('; ')}`);
    const bundle = verifyAndLoadLoaBundle(join(bundleOutput, 'aleph-for-loa'));
    expect(bundle.lock.run_format_version === '1.5.0-provisional',
      `temporary bundle retained ${bundle.lock.run_format_version}`);
    pass('immutable temporary Loa bundle activates run format 1.5');

    const pinnedCoreAuthority: PinnedCoreAuthority = {
      source_kind: 'retained-immutable-bundle',
      root: bundle.root,
      lock: bundle.lock,
      expected_bundle_digest: bundle.lock.bundle.digest,
      expected_core_digest: bundle.lock.core.tree_digest,
      files: bundle.files,
      file_bytes: bundle.fileBytes,
    };
    const requirementRef = 'core:docs/architecture/04-pipeline-stages-and-dod.md#S5 — Disposition pass';
    const resolvedRequirement = resolvePinnedCoreRequirement(pinnedCoreAuthority, requirementRef);
    expect(resolvedRequirement.path === 'docs/architecture/04-pipeline-stages-and-dod.md'
      && resolvedRequirement.selector === 'S5 — Disposition pass'
      && resolvedRequirement.selector_kind === 'heading'
      && resolvedRequirement.bytes.byteLength > 0,
    'pinned Core requirement did not reopen the exact retained heading bytes');
    pass('requirement_ref resolves only through the retained immutable bundle and exact Core bytes');

    const tamperedCoreBytes = new Map(bundle.fileBytes);
    tamperedCoreBytes.set(
      resolvedRequirement.path,
      Buffer.concat([tamperedCoreBytes.get(resolvedRequirement.path) || Buffer.alloc(0), Buffer.from('\nmutated\n')]),
    );
    expectThrows(
      () => resolvePinnedCoreRequirement({
        ...pinnedCoreAuthority,
        file_bytes: tamperedCoreBytes,
      }, requirementRef),
      /retained Core bytes are absent or disagree with the pinned inventory/u,
      'tampered retained Core requirement bytes',
    );
    pass('requirement_ref resolution fails closed on retained Core byte drift');

    const runId = 'RUN-internal-ambiguity-lifecycle';
    const loaRoot = join(tempRoot, 'loa-root');
    const capabilitiesPath = join(
      loaRoot,
      'grimoires',
      'loa',
      'aleph',
      'host-capabilities.json',
    );
    mkdirSync(dirname(capabilitiesPath), { recursive: true });
    cpSync(HOST_CAPABILITIES_FIXTURE, capabilitiesPath);
    const s0RunId = 'RUN-s0-slice5-coexistence';
    const s0Ids: IdSource = { nextRunId: () => s0RunId, nextCallId: () => 'CALL-S0' };
    const s0InputPath = join(loaRoot, 'fixture-input', 'SRC-0401-source-walk.txt');
    mkdirSync(dirname(s0InputPath), { recursive: true });
    cpSync(
      join(FIXTURE_ROOT, 'corpus/sources/SRC-0401-source-walk.txt'),
      s0InputPath,
    );
    const started = startLoaRun(
      [s0InputPath],
      {
        loaRoot,
        bundleRoot: bundle.root,
        capabilitiesPath,
        allowSimulation: true,
        clock: S0_START_CLOCK,
        idSource: s0Ids,
      },
    );
    expect(started.result === 'BLOCKED', `shipped S0 start failed: ${started.errors.join('; ')}`);
    const s0RunDir = join(loaRoot, 'grimoires', 'loa', 'aleph', 'runs', s0RunId);
    const s0Corpus = verifyCorpusSnapshot(s0RunDir);
    const frozen = recordS0AuthorityResponse(s0RunId, fixtureS0Response(s0Corpus), {
      loaRoot,
      allowSimulation: true,
      clock: S0_RESPONSE_CLOCK,
    });
    expect(frozen.result === 'PASS', `shipped S0 response failed: ${frozen.errors.join('; ')}`);
    const s0FrozenCorpus = verifyCorpusSnapshot(s0RunDir);
    const s0Request = readFileSync(join(s0RunDir, 'control/gates/GATE-S0-request.json'));
    const s0Response = readFileSync(join(s0RunDir, 'control/gates/GATE-S0-response.json'));
    const s0State = readRunState(s0RunDir);
    const s0Manifest = readFileSync(join(s0RunDir, 'run-manifest.md'), 'utf8');
    pass('shipped S0 flow retains genuine request and response records');

    const runDir = join(loaRoot, 'grimoires', 'loa', 'aleph', 'runs', runId);
    mkdirSync(dirname(runDir), { recursive: true });
    cpSync(FIXTURE_ROOT, runDir, { recursive: true });
    writeFileSync(join(runDir, 'control/gates/GATE-S0-request.json'), s0Request);
    writeFileSync(join(runDir, 'control/gates/GATE-S0-response.json'), s0Response);
    rmSync(join(runDir, 'control/gates/GATE-S4-AMB-1503-A1-Q1-request.json'));
    rmSync(join(runDir, 'control/gates/GATE-S4-AMB-1503-A1-Q1-response.json'));
    rmSync(join(
      runDir,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M1.json',
    ));
    rmSync(join(runDir, 'verification/harness/S4-material-impact/VER-1591.md'));
    mkdirSync(join(runDir, 'control', 'transactions'), { recursive: true });
    mkdirSync(join(runDir, 'control', 'gates'), { recursive: true });
    writeFileSync(
      join(runDir, 'control', 'original-bundle.lock.json'),
      readVerifiedBundleLock(bundle),
    );
    const profile = loadLoaProfile(defaultProfilePath(bundle.root));
    const host = validateResolvedHost(
      readJsonFile(HOST_CAPABILITIES_FIXTURE),
      profile.value,
      { allowSimulation: true },
    );
    mkdirSync(join(runDir, 'control', 'runtime'), { recursive: true });
    const runtime = captureRuntimeSnapshot({
      runId,
      bundle,
      profile,
      host,
      capturedAt: FIXED_TIME,
      outputPath: join(runDir, 'control', 'runtime', 'snapshot.json'),
    });
    const targetCorpus = structuredClone(s0FrozenCorpus);
    targetCorpus.run_id = runId;
    targetCorpus.files[0].source_id = 'SRC-0401';
    targetCorpus.files[0].relative_path = 'SRC-0401-source-walk.txt';
    targetCorpus.files[0].frozen_path = 'corpus/sources/SRC-0401-source-walk.txt';
    targetCorpus.tree_digest = digestTreeRecords(targetCorpus.files.map((file) => ({
      path: file.frozen_path,
      digest: file.digest,
    })));
    writeJsonAtomic(join(runDir, 'control', 'corpus.snapshot.json'), targetCorpus);
    const targetManifest = s0Manifest
      .replaceAll(s0RunId, runId)
      .replace(s0State.identity.runtime.digest, runtime.tree_digest)
      .replace(s0FrozenCorpus.tree_digest, targetCorpus.tree_digest)
      .replace(
        '\n\n## Authority sign-offs',
        '\n| 3 | DISTILLING | 2026-08-14 08:20 UTC | fixture-simulated Loa orchestrator | Slice 5 process proof entered S4. |\n\n## Authority sign-offs',
      );
    writeFileSync(join(runDir, 'run-manifest.md'), targetManifest);
    const fullAmbiguities = Buffer.from(
      readFileSync(join(runDir, 'ledgers/internal-ambiguities.md'), 'utf8')
        .split('\n')
        .filter((line) => !line.startsWith('| AMB-1503 | 1 | 1 | carry-unresolved |'))
        .join('\n'),
      'utf8',
    );
    const finalRunLog = readFileSync(join(runDir, 'run-log.md'), 'utf8');
    writeFileSync(join(runDir, 'run-log.md'), preC1RunLog(finalRunLog));
    writeFileSync(join(runDir, 'ledgers/internal-ambiguities.md'), emptyAmbiguityLedger(runId));
    const state = initialState(runId, bundle, profile, host, runtime);
    state.corpus = {
      state: 'frozen',
      inventory_ref: 'control/corpus.snapshot.json',
      tree_digest: targetCorpus.tree_digest,
    };
    writeRunState(runDir, state);
    const validated = validatedFixtureReturn(bundle, runDir, state);
    const writer = new LedgerWriter(runDir, CLOCK);

    const relationPath = join(runDir, 'ledgers/relations.md');
    const relationBefore = readFileSync(relationPath);
    writer.append(
      'ledgers/relations.md',
      validated,
      () => '<!-- fixture legal pre-C1 relation write -->',
    );
    expect(!readFileSync(relationPath).equals(relationBefore),
      'legal pre-C1 relation append left relation bytes unchanged');
    pass('relation append succeeds in the legal pre-C1 window');

    writer.advanceSlice5ClosurePhase('S4-C1-relations-closed');
    expect(readFileSync(join(runDir, 'run-log.md'), 'utf8')
      .includes('closure_phase: S4-C1-relations-closed'), 'C1 marker was not retained');
    pass('C1 advances only after prospective K2.16 validation');

    const relationAtC1 = readFileSync(relationPath);
    expectThrows(
      () => writer.append('ledgers/relations.md', validated, () => '<!-- forbidden append -->'),
      /post-C1 canonical relation append refused before bytes change/u,
      'post-C1 relation append',
    );
    expect(readFileSync(relationPath).equals(relationAtC1), 'post-C1 append changed relation bytes');
    pass('post-C1 relation append is refused before bytes change');

    expectThrows(
      () => writer.remove('ledgers/relations.md'),
      /post-C1 canonical relation delete refused before bytes change/u,
      'post-C1 relation deletion',
    );
    expect(readFileSync(relationPath).equals(relationAtC1), 'post-C1 deletion changed relation bytes');
    pass('post-C1 relation deletion is refused before bytes change');

    expectThrows(
      () => writer.replace('ledgers/relations.md', validated, () => 'forbidden'),
      /post-C1 canonical relation replace refused before bytes change/u,
      'post-C1 relation replacement',
    );
    expect(readFileSync(relationPath).equals(relationAtC1), 'post-C1 replacement changed relation bytes');
    pass('post-C1 relation edit/replacement is refused before bytes change');

    expectThrows(
      () => writer.retarget('ledgers/relations.md', validated, () => 'forbidden'),
      /post-C1 canonical relation retarget refused before bytes change/u,
      'post-C1 relation retarget',
    );
    expect(readFileSync(relationPath).equals(relationAtC1), 'post-C1 retarget changed relation bytes');
    pass('post-C1 relation retarget is refused before bytes change');

    const logAtC1 = readFileSync(join(runDir, 'run-log.md'));
    expectThrows(
      () => writer.advanceSlice5ClosurePhase('S4-C1-relations-closed'),
      /not the single next durable phase/u,
      'silent C1 rerun',
    );
    expect(readFileSync(join(runDir, 'run-log.md')).equals(logAtC1),
      'silent C1 rerun changed run-log bytes');
    pass('silent C1 rerun is refused before bytes change');

    const ambiguityPath = join(runDir, 'ledgers/internal-ambiguities.md');
    writeFileSync(ambiguityPath, fullAmbiguities);
    const runtimeCli = join(
      runtime.bundle.root,
      'runtime-js',
      'adapters',
      'loa',
      'src',
      'cli.js',
    );
    const workerHandoffCli = join(
      runtime.bundle.root,
      'runtime-js',
      'adapters',
      'loa',
      'src',
      'worker-dispatch.js',
    );
    const resumed = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'resume',
      runId,
    ]);
    const resumeDetails = resumed.details as Record<string, JsonValue>;
    const resumeSlice5 = resumeDetails.slice5 as Record<string, JsonValue>;
    expect(
      resumed.result === 'PASS'
        && JSON.stringify(resumeSlice5.required_roles) === JSON.stringify([
          'ambiguity-producer',
          'ambiguity-reviewer',
          'material-impact-producer',
          'material-impact-reviewer',
        ]),
      `public resume did not expose exact Slice 5 next work: ${JSON.stringify(resumed)}`,
    );
    pass('public resume exposes the exact four-role Slice 5 first-unmet work');

    const runtimeBundle = verifyAndLoadLoaBundle(runtime.bundle.root);
    const assemblyInputRoot = join(runDir, 'control', 'worker-assembly-inputs');
    const fixtureReturnRoot = join(runDir, 'control', 'fixture-worker-returns');
    mkdirSync(assemblyInputRoot, { recursive: true });
    mkdirSync(fixtureReturnRoot, { recursive: true });
    const operatorRoleCases: Array<{
      role: 'ambiguity-producer'
        | 'ambiguity-reviewer'
        | 'material-impact-producer'
        | 'material-impact-reviewer';
      kind: 'producer' | 'refuter';
      producerContextId: string | null;
    }> = [
      {
        role: 'ambiguity-producer',
        kind: 'producer',
        producerContextId: null,
      },
      {
        role: 'ambiguity-reviewer',
        kind: 'refuter',
        producerContextId: 'CTX-SLICE5-AMBIGUITY-PRODUCER',
      },
      {
        role: 'material-impact-producer',
        kind: 'producer',
        producerContextId: null,
      },
      {
        role: 'material-impact-reviewer',
        kind: 'refuter',
        producerContextId: 'CTX-SLICE5-MATERIAL-PRODUCER',
      },
    ];
    for (const [index, roleCase] of operatorRoleCases.entries()) {
      const callId = `CALL-SLICE5-OPERATOR-${String(index + 1).padStart(4, '0')}`;
      const inputPath = join(assemblyInputRoot, `${callId}.json`);
      writeJsonAtomic(inputPath, {
        format: 'aleph-loa-worker-assembly-input/v1',
        call_id: callId,
        run_id: runId,
        stage: 'S4',
        role: roleCase.role,
        kind: roleCase.kind,
        allowlist: [],
        withheld: withheldInventory(runtimeBundle, runDir, roleCase.role, []),
        task_line: 'Return only the exact bounded Slice 5 structured result.',
        producer_context_id: roleCase.producerContextId,
        downstream_operations: [],
      });
      const assembledResult = runJsonProcess(workerHandoffCli, [
        'assemble',
        '--bundle',
        runtime.bundle.root,
        '--run',
        runDir,
        '--input',
        inputPath,
        '--json',
      ]);
      const workerBundleRoot = String(assembledResult.worker_bundle_root);
      const request = verifyWorkerBundle(workerBundleRoot);
      expect(
        assembledResult.result === 'PASS'
          && request.role === roleCase.role
          && request.kind === roleCase.kind
          && request.isolation.producer_context_id === roleCase.producerContextId,
        `${roleCase.role} operator assembly did not retain exact typed inputs`,
      );
      const returnRoot = join(runDir, 'control', 'worker-returns', callId);
      const prepared = runJsonProcess(workerHandoffCli, [
        'prepare',
        '--worker-bundle',
        workerBundleRoot,
        '--return-root',
        returnRoot,
        '--capabilities',
        runtime.host_receipt.path,
        '--json',
      ]);
      expect(prepared.result === 'PASS', `${roleCase.role} prepare did not pass`);
      const rawPath = join(fixtureReturnRoot, `${callId}.json`);
      writeFileSync(rawPath, stableJsonBytes(slice5WorkerReturn(roleCase.role)));
      runFixtureDispatchProcess(
        workerHandoffCli,
        workerBundleRoot,
        returnRoot,
        rawPath,
        `CTX-SLICE5-OPERATOR-${String(index + 1).padStart(4, '0')}`,
      );
      const acceptedProcess = runJsonProcess(workerHandoffCli, [
        'accept',
        '--worker-bundle',
        workerBundleRoot,
        '--return-root',
        returnRoot,
        '--json',
      ]);
      expect(
        acceptedProcess.result === 'PASS',
        `${roleCase.role} shipped accept path rejected its canonical fixture return`,
      );
      const accepted = acceptLoaWorkerHandoff({
        workerBundleRoot,
        returnRoot,
      });
      expect(
        accepted.validated !== null
          && accepted.validated.simulation?.kind === 'fixture-simulated',
        `${roleCase.role} accepted result lost validation or simulation identity`,
      );
      writer.append(
        `verification/operator-process/${roleCase.role}.md`,
        accepted.validated,
        (data) => `# Fixture-simulated ${roleCase.role} operator result\n\n`
          + `\`\`\`json\n${JSON.stringify(data)}\n\`\`\`\n`,
      );
    }
    pass('public resume through shipped assemble, prepare, dispatch, accept, and writer works for all four Slice 5 roles');

    const crashT52BeforeMaterial = join(tempRoot, 'crash-01-t52-before-material');
    cpSync(runDir, crashT52BeforeMaterial, { recursive: true });
    expectThrows(
      () => new LedgerWriter(crashT52BeforeMaterial, CLOCK)
        .advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized'),
      /latest unresolved T5\.2 assessment has no material-impact history at C2/u,
      'C2 with unresolved ambiguity lacking material review',
    );
    pass('real C2 closure path rejects an unresolved ambiguity with no material-impact history');
    const t52Line = readFileSync(ambiguityPath, 'utf8')
      .split('\n')
      .find((line) => line.startsWith('| AMB-1503 | 1 |'));
    expect(t52Line !== undefined, 'fixture lacks AMB-1503 T5.2 row');
    const ambiguityReviewPath = join(
      runDir,
      'verification/harness/S4-ambiguities/VER-1503.md',
    );
    const operativeScope = {
      affected_ids: ['CC-0413'],
      impact_rows: [{
        affected_id: 'CC-0413',
        operation_kind: 'load-bearing-reasoning' as const,
        requirement_ref: 'core:docs/architecture/04-pipeline-stages-and-dod.md#S5 — Disposition pass',
        unresolved_treatment: 'carry-or-restriction' as const,
        consequence_if_unresolved: 'The downstream use remains explicitly contingent on the unresolved expression.',
      }],
    };
    const materialSubject: MaterialImpactSubject = {
      format: 'aleph-internal-ambiguity-material-impact-review-subject/v1',
      run_id: runId,
      ambiguity_id: 'AMB-1503',
      assessment_seq: 1,
      material_impact_seq: 1,
      t5_2_assessment_ref: `internal-ambiguity:T5.2:AMB-1503:A1@${sha256Digest(t52Line)}`,
      t5_2_review_subject_digest: 'sha256:971c8b4b48522d87dc994a48823f1f4eabce05cd1c990b1bd08f506e5caf201d',
      t5_2_review_ref: `ambiguity-review-verdict:VER-1503@${sha256Digest(readFileSync(ambiguityReviewPath))}`,
      c1_relation_basis_ref: 'none',
      materiality_class: 'C',
      operative_scope: operativeScope,
      source_locators: ['SRC-0401:L8-L8'],
      reviewed_unaffected_ids: [],
      unresolved_statement: 'The frozen same-source bytes do not identify one local referent.',
      review_proposition: 'class-B-or-C-and-canonical-operative-scope-complete-and-accurate-under-cited-Core-requirements',
      proposed_by: 'invocation:material-impact-producer-0001',
    };
    const materialSubjectText = materialImpactSubjectJson(materialSubject);
    const materialDigest = materialImpactSubjectDigest(materialSubject);
    const materialSubjectPath = join(
      runDir,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M1.json',
    );
    mkdirSync(dirname(materialSubjectPath), { recursive: true });
    writeFileSync(materialSubjectPath, materialSubjectText);
    const crashMaterialBeforeReview = join(tempRoot, 'crash-02-material-before-review');
    cpSync(runDir, crashMaterialBeforeReview, { recursive: true });
    const materialReviewPath = join(
      runDir,
      'verification/harness/S4-material-impact/VER-1591.md',
    );
    mkdirSync(dirname(materialReviewPath), { recursive: true });
    const materialReviewTextM1 = materialReviewText(
      'VER-1591',
      materialDigest,
      'upheld',
      'fixture Class C basis may proceed to bounded human procedure',
    );
    writeFileSync(materialReviewPath, materialReviewTextM1);
    const crashReviewBeforeRequest = join(tempRoot, 'crash-03-review-before-request');
    cpSync(runDir, crashReviewBeforeRequest, { recursive: true });
    const cannotDetermineRun = join(tempRoot, 'cannot-determine-material-review');
    cpSync(runDir, cannotDetermineRun, { recursive: true });
    writeFileSync(
      join(cannotDetermineRun, 'verification/harness/S4-material-impact/VER-1591.md'),
      materialReviewTextM1.replace('| verdict | upheld |', '| verdict | cannot-determine |'),
    );
    expectThrows(
      () => new LedgerWriter(cannotDetermineRun, CLOCK)
        .advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized'),
      /latest material-impact verdict must be upheld to continue/u,
      'cannot-determine material review at C2',
    );
    pass('cannot-determine material review blocks C2 until a legal material successor exists');

    const bogusRequirementRun = join(tempRoot, 'bogus-pinned-requirement');
    cpSync(runDir, bogusRequirementRun, { recursive: true });
    const bogusSubjectPath = join(
      bogusRequirementRun,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M1.json',
    );
    const bogusSubject = JSON.parse(readFileSync(bogusSubjectPath, 'utf8')) as MaterialImpactSubject;
    bogusSubject.operative_scope.impact_rows[0].requirement_ref =
      'core:docs/architecture/04-pipeline-stages-and-dod.md#DOES-NOT-EXIST';
    writeFileSync(bogusSubjectPath, materialImpactSubjectJson(bogusSubject));
    expectThrows(
      () => new LedgerWriter(bogusRequirementRun, CLOCK)
        .advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized'),
      /does not resolve under the run pin/u,
      'bogus pinned requirement in real C2 path',
    );
    pass('real C2 closure rejects a grammatically legal requirement_ref absent from pinned Core');

    const tamperedPinnedCoreRun = join(tempRoot, 'tampered-pinned-core');
    cpSync(runDir, tamperedPinnedCoreRun, { recursive: true });
    const retainedCorePath = join(
      tamperedPinnedCoreRun,
      'control/runtime/bundle/docs/architecture/04-pipeline-stages-and-dod.md',
    );
    chmodSync(retainedCorePath, 0o600);
    writeFileSync(
      retainedCorePath,
      Buffer.concat([readFileSync(retainedCorePath), Buffer.from('\nretained tamper\n', 'utf8')]),
    );
    expectThrows(
      () => new LedgerWriter(tamperedPinnedCoreRun, CLOCK)
        .advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized'),
      /retained Core file disagrees with its inventory/u,
      'tampered retained Core in real C2 path',
    );
    pass('real C2 closure rejects retained Core tampering under the unchanged lock');

    const missingPinnedCoreRun = join(tempRoot, 'missing-pinned-core');
    cpSync(runDir, missingPinnedCoreRun, { recursive: true });
    const missingRetainedPath = join(
      missingPinnedCoreRun,
      'control/runtime/bundle/docs/architecture/04-pipeline-stages-and-dod.md',
    );
    chmodSync(missingRetainedPath, 0o600);
    rmSync(missingRetainedPath);
    expectThrows(
      () => new LedgerWriter(missingPinnedCoreRun, CLOCK)
        .advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized'),
      /retained Core file is absent/u,
      'source checkout fallback for missing pinned Core',
    );
    pass('current source checkout cannot rescue a missing run-pinned Core file');
    const authoritySubject = buildProceduralAuthoritySubject({
      run_id: runId,
      ambiguity_id: 'AMB-1503',
      assessment_seq: 1,
      t5_2_assessment_ref: materialSubject.t5_2_assessment_ref,
      t5_2_review_subject_digest: 'sha256:971c8b4b48522d87dc994a48823f1f4eabce05cd1c990b1bd08f506e5caf201d',
      t5_2_review_ref: materialSubject.t5_2_review_ref,
      prior_indeterminate_review_refs: [],
      candidate_state: 'null-no-candidate',
      candidate_refs: [],
      carry_state: 'none',
      affected_relation_ids: [],
      c1_relation_basis_ref: 'none',
      material_impact_seq: 1,
      material_impact_subject_ref: `material-impact-subject:AMB-1503:A1:M1@${materialDigest}`,
      material_impact_review_ref: `material-impact-verdict:VER-1591@${sha256Digest(readFileSync(materialReviewPath))}`,
      operative_scope: structuredClone(operativeScope),
      source_locators: ['SRC-0401:L8-L8'],
      reviewed_unaffected_ids: [],
      unresolved_statement: 'The frozen same-source bytes do not identify one local referent.',
    });
    const request = buildProceduralAuthorityRequest({
      request_seq: 1,
      subject: authoritySubject,
      presentation: true,
      required_authority_identity: 'human:fixture-operator',
      prepared_by: 'invocation:loa-orchestrator',
      requested_at: FIXED_TIME,
    });

    const recoveredMaterialPath = join(
      crashT52BeforeMaterial,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M1.json',
    );
    mkdirSync(dirname(recoveredMaterialPath), { recursive: true });
    writeFileSync(recoveredMaterialPath, materialSubjectText);
    expect(readFileSync(recoveredMaterialPath, 'utf8') === materialSubjectText
      && !existsSync(join(crashT52BeforeMaterial, `control/gates/${request.request_id}-request.json`)),
    'crash point 1 did not resume at the exact missing M subject');
    pass('crash matrix 1: T5.2 before M subject resumes at the exact M1 write');

    const recoveredReviewPath = join(
      crashMaterialBeforeReview,
      'verification/harness/S4-material-impact/VER-1591.md',
    );
    mkdirSync(dirname(recoveredReviewPath), { recursive: true });
    writeFileSync(recoveredReviewPath, materialReviewTextM1);
    expect(readFileSync(recoveredReviewPath, 'utf8') === materialReviewTextM1
      && !existsSync(join(crashMaterialBeforeReview, `control/gates/${request.request_id}-request.json`)),
    'crash point 2 did not resume at the exact missing material verifier');
    pass('crash matrix 2: M subject before verifier resumes at the exact upheld review write');

    openHumanAuthorityGate(crashReviewBeforeRequest, {
      gateId: request.request_id,
      gateType: 'internal-ambiguity-procedural-decision',
      stage: 'S4',
      now: FIXED_TIME,
      request: request as unknown as JsonValue,
    });
    expect(readRunState(crashReviewBeforeRequest).execution.gate?.id === request.request_id,
      'crash point 3 did not resume at the exact missing request');
    pass('crash matrix 3: verifier before request resumes at the exact Q1 durable gate');

    openHumanAuthorityGate(runDir, {
      gateId: request.request_id,
      gateType: 'internal-ambiguity-procedural-decision',
      stage: 'S4',
      now: FIXED_TIME,
      request: request as unknown as JsonValue,
    });
    expect(readRunState(runDir).execution.gate?.id === request.request_id,
      'procedural request did not become the one active gate');
    pass('Class C procedural request is retained as the one active human gate');

    const crashRequestBeforeHalt = join(tempRoot, 'crash-04-request-before-halt');
    cpSync(runDir, crashRequestBeforeHalt, { recursive: true });
    const openTransactionPath = join(
      crashRequestBeforeHalt,
      'control/transactions',
      `TXN-authority-open-${request.request_id}.json`,
    );
    const committedOpen = readJsonFile(openTransactionPath) as Record<string, JsonValue>;
    const { committed_at: _committedOpenAt, ...preparedOpen } = committedOpen;
    writeRunState(crashRequestBeforeHalt, readRunState(crashReviewBeforeRequest));
    writeJsonAtomic(openTransactionPath, { ...preparedOpen, status: 'prepared' });
    const recoveredOpen = recoverPendingAuthorityTransactions(crashRequestBeforeHalt, CLOCK);
    expect(recoveredOpen.committed.length === 1
      && readRunState(crashRequestBeforeHalt).execution.gate?.id === request.request_id,
    'prepared request transaction did not recover its durable halt and active pointer');
    pass('crash matrix 4: request before durable halt recovers the same Q1 and active gate');

    expectThrows(
      () => openHumanAuthorityGate(runDir, {
        gateId: 'GATE-S4-AMB-1503-A1-Q2',
        gateType: 'internal-ambiguity-procedural-decision',
        stage: 'S4',
        now: FIXED_TIME,
        request: request as unknown as JsonValue,
      }),
      /already awaiting a response/u,
      'parallel procedural request',
    );
    pass('a parallel procedural request is refused while Q1 is active');

    const requestBytes = Buffer.from(proceduralAuthorityRequestJson(request), 'utf8');
    const authorityCheckpoint = join(tempRoot, 'authority-checkpoint');
    cpSync(runDir, authorityCheckpoint, { recursive: true });
    const decoyRun = join(tempRoot, 'decoy-upheld-verdict');
    cpSync(authorityCheckpoint, decoyRun, { recursive: true });
    const decoyReviewPath = join(
      decoyRun,
      'verification/harness/S4-material-impact/VER-1591.md',
    );
    const decoyReview = readFileSync(decoyReviewPath, 'utf8')
      .replace('| verdict | upheld |', '| verdict | refuted |')
      + '\n| field | value |\n|-------|-------|\n| verdict | upheld |\n';
    writeFileSync(decoyReviewPath, decoyReview);
    const decoySubject = structuredClone(authoritySubject);
    decoySubject.material_impact_review_ref =
      `material-impact-verdict:VER-1591@${sha256Digest(decoyReview)}`;
    expectThrows(
      () => new LedgerWriter(decoyRun, CLOCK).openProceduralAuthorityFollowup({
        request_id: request.request_id,
        reason: 'presentation-only-replacement',
        next_subject: decoySubject,
        presentation: true,
        required_authority_identity: 'human:fixture-operator',
        prepared_by: 'invocation:loa-orchestrator',
        requested_at: '2040-01-02T03:12:00.000Z',
      }),
      /exactly one canonical field\/value table/u,
      'refuted verifier with decoy upheld table',
    );
    pass('Core-owned structured verifier rejects refuted verdict plus decoy upheld table');
    const reviewFailures: Array<{
      slug: string;
      name: string;
      mutate: (text: string) => string;
      updateDigest: boolean;
      pattern: RegExp;
    }> = [
      {
        slug: 'duplicate-verdict',
        name: 'duplicate verifier verdict fields',
        mutate: (text) => text.replace(
          '| verdict | upheld |',
          '| verdict | upheld |\n| verdict | upheld |',
        ),
        updateDigest: true,
        pattern: /verifier field verdict must occur exactly once/u,
      },
      {
        slug: 'missing-table',
        name: 'missing canonical verifier table',
        mutate: (text) => text.replace('| field | value |', '| key | value |'),
        updateDigest: true,
        pattern: /exactly one canonical field\/value table/u,
      },
      {
        slug: 'wrong-target',
        name: 'wrong material verifier target',
        mutate: (text) => text.replace(
          `internal-ambiguity-material-impact-review-subject:${materialDigest}`,
          `internal-ambiguity-material-impact-review-subject:sha256:${'0'.repeat(64)}`,
        ),
        updateDigest: true,
        pattern: /target or verdict does not authorize a request/u,
      },
      {
        slug: 'wrong-digest',
        name: 'wrong material verifier digest',
        mutate: (text) => text,
        updateDigest: false,
        pattern: /review ref does not resolve to one exact retained verifier/u,
      },
    ];
    for (const [index, failure] of reviewFailures.entries()) {
      const failureRun = join(tempRoot, `authority-basis-${failure.slug}`);
      cpSync(authorityCheckpoint, failureRun, { recursive: true });
      const reviewPath = join(
        failureRun,
        'verification/harness/S4-material-impact/VER-1591.md',
      );
      const reviewText = failure.mutate(readFileSync(reviewPath, 'utf8'));
      writeFileSync(reviewPath, reviewText);
      const nextSubject = structuredClone(authoritySubject);
      nextSubject.material_impact_review_ref = failure.updateDigest
        ? `material-impact-verdict:VER-1591@${sha256Digest(reviewText)}`
        : `material-impact-verdict:VER-1591@sha256:${'0'.repeat(64)}`;
      expectThrows(
        () => new LedgerWriter(failureRun, CLOCK).openProceduralAuthorityFollowup({
          request_id: request.request_id,
          reason: 'presentation-only-replacement',
          next_subject: nextSubject,
          presentation: true,
          required_authority_identity: 'human:fixture-operator',
          prepared_by: 'invocation:loa-orchestrator',
          requested_at: `2040-01-02T03:${String(13 + index).padStart(2, '0')}:00.000Z`,
        }),
        failure.pattern,
        failure.name,
      );
      pass(`Core-owned structured verifier rejects ${failure.name}`);
    }
    const actionCases: Array<{
      action: Exclude<ProceduralAction, 'carry-unresolved'>;
      halt: string | null;
      followup: 'nonterminal-response' | 'actual-resume-after-suspensive-block' | null;
    }> = [
      { action: 'restrict-downstream-use', halt: null, followup: null },
      { action: 'inspect-source', halt: 'S4_C2_FOLLOWUP_REQUEST_REQUIRED', followup: 'nonterminal-response' },
      { action: 'block-at-current-barrier', halt: 'BLOCKED_AT_S4_C2', followup: 'actual-resume-after-suspensive-block' },
      { action: 'request-successor-corpus-run', halt: 'SUCCESSOR_CORPUS_RUN_REQUIRED', followup: null },
      { action: 'record-human-observation', halt: 'S4_C2_FOLLOWUP_REQUEST_REQUIRED', followup: 'nonterminal-response' },
    ];
    for (const [index, actionCase] of actionCases.entries()) {
      const actionRun = join(tempRoot, `action-${actionCase.action}`);
      cpSync(authorityCheckpoint, actionRun, { recursive: true });
      const independentBefore = new Map([
        ['ledgers/disposition-ledger.md', readFileSync(join(actionRun, 'ledgers/disposition-ledger.md'))],
        ['ledgers/evidence-roles.md', readFileSync(join(actionRun, 'ledgers/evidence-roles.md'))],
        ['ledgers/external-referents.md', readFileSync(join(actionRun, 'ledgers/external-referents.md'))],
        ['ledgers/relations.md', readFileSync(join(actionRun, 'ledgers/relations.md'))],
      ]);
      const observationBytes = Buffer.from(' exact human observation bytes \n', 'utf8');
      const actionResponse = buildProceduralAuthorityResponse({
        request,
        request_bytes: requestBytes,
        authority_identity: 'human:fixture-operator',
        selected_action: actionCase.action,
        observation: actionCase.action === 'record-human-observation'
          ? exactTextBlob(observationBytes)
          : null,
        comment: actionCase.action === 'inspect-source'
          ? exactTextBlob(Buffer.from(' inspect only; no semantic instruction ', 'utf8'))
          : null,
        recorded_at: `2040-01-02T03:${String(20 + index).padStart(2, '0')}:00.000Z`,
      });
      recordHumanAuthorityDecision(actionRun, {
        gateId: request.request_id,
        authorityIdentity: 'human:fixture-operator',
        decision: 'approve',
        recordedAt: actionResponse.recorded_at,
        simulation: { kind: 'fixture-simulated' },
        response: actionResponse as unknown as JsonValue,
      });
      const actionWriter = new LedgerWriter(actionRun, CLOCK);
      actionWriter.appendProceduralAuthorityResponse(request.request_id);
      const actionLedger = readFileSync(join(actionRun, 'ledgers/internal-ambiguities.md'), 'utf8');
      expect(actionLedger.includes(`| AMB-1503 | 1 | 1 | ${actionCase.action} | none |`),
        `${actionCase.action} did not append the exact positive T5.3 row`);
      const actionState = readRunState(actionRun);
      expect(actionState.execution.halt?.code === actionCase.halt
        || (actionCase.halt === null && actionState.execution.halt === null),
      `${actionCase.action} produced the wrong retained halt state`);
      if (actionCase.action === 'record-human-observation') {
        const responseBytes = readFileSync(join(
          actionRun,
          `control/gates/${request.request_id}-response.json`,
        ));
        expect(responseBytes.includes(Buffer.from(exactTextBlob(observationBytes).bytes_base64, 'utf8')),
          'record-human-observation did not retain exact supplied bytes');
      }
      if (actionCase.action === 'restrict-downstream-use') {
        expect(JSON.stringify(restrictionOverlay(authoritySubject.operative_scope))
          === JSON.stringify([{
            affected_id: 'CC-0413',
            operation_kind: 'load-bearing-reasoning',
            requirement_ref: 'core:docs/architecture/04-pipeline-stages-and-dod.md#S5 — Disposition pass',
          }]), 'restriction overlay is not the exact surgical Core tuple projection');
        const restrictedOperation = {
          affected_id: 'CC-0413',
          operation_kind: 'load-bearing-reasoning' as const,
          requirement_ref: 'core:docs/architecture/04-pipeline-stages-and-dod.md#S5 — Disposition pass',
        };
        expectThrows(
          () => assembleWorkerBundle({
            bundle,
            runDir: actionRun,
            callId: 'CALL-SLICE5-RESTRICTED-S5',
            runId,
            stage: 'S5',
            role: 'disposition-judge',
            kind: 'producer',
            allowlist: ['ledgers/disposition-ledger.md'],
            withheld: withheldInventory(
              bundle,
              actionRun,
              'disposition-judge',
              ['ledgers/disposition-ledger.md'],
              'S5',
            ),
            downstreamOperations: [restrictedOperation],
            taskLine: 'Attempt only the exact typed downstream operation supplied by Core.',
            modelIdentity: readRunState(actionRun).identity.models['disposition-judge'],
          }),
          /prohibited by retained procedural restriction/u,
          'restricted S5 operation',
        );
        const neighboringOperation = {
          ...restrictedOperation,
          affected_id: 'CC-0414',
        };
        const allowed = assembleWorkerBundle({
          bundle,
          runDir: actionRun,
          callId: 'CALL-SLICE5-ALLOWED-S5',
          runId,
          stage: 'S5',
          role: 'disposition-judge',
          kind: 'producer',
          allowlist: ['ledgers/disposition-ledger.md'],
          withheld: withheldInventory(
            bundle,
            actionRun,
            'disposition-judge',
            ['ledgers/disposition-ledger.md'],
            'S5',
          ),
          downstreamOperations: [neighboringOperation],
          taskLine: 'Perform only the exact typed neighboring operation supplied by Core.',
          modelIdentity: readRunState(actionRun).identity.models['disposition-judge'],
        });
        expect(allowed.request.procedural_restrictions.some((restriction) => (
          JSON.stringify(restriction) === JSON.stringify(restrictedOperation)
        ))
          && JSON.stringify(allowed.request.downstream_operations)
            === JSON.stringify([neighboringOperation]),
        'downstream worker request did not consume the exact retained restriction separately');
        pass('real S5 worker-bundle path blocks the exact restricted tuple and permits an unaffected neighbor');
      }
      if (actionCase.followup) {
        const q2 = actionWriter.openProceduralAuthorityFollowup({
          request_id: request.request_id,
          reason: actionCase.followup,
          next_subject: authoritySubject,
          presentation: true,
          required_authority_identity: 'human:fixture-operator',
          prepared_by: 'invocation:loa-orchestrator',
          requested_at: `2040-01-02T04:${String(20 + index).padStart(2, '0')}:00.000Z`,
        });
        expect(q2.request_id === 'GATE-S4-AMB-1503-A1-Q2'
          && readRunState(actionRun).execution.gate?.id === q2.request_id,
        `${actionCase.action} did not create exactly one active Q2 request`);
        const replayed = actionWriter.openProceduralAuthorityFollowup({
          request_id: request.request_id,
          reason: actionCase.followup,
          next_subject: authoritySubject,
          presentation: true,
          required_authority_identity: 'human:fixture-operator',
          prepared_by: 'invocation:loa-orchestrator',
          requested_at: `2040-01-02T04:${String(20 + index).padStart(2, '0')}:00.000Z`,
        });
        expect(replayed.request_id === q2.request_id,
          `${actionCase.action} Q2 recovery was not idempotent`);
        if (actionCase.action === 'inspect-source') {
          pass('crash matrix 7: nonterminal response before Q+1 resumes with one idempotent Q2');
        }
        if (actionCase.action === 'block-at-current-barrier') {
          expect(readRunState(actionRun).execution.core_state === 'DISTILLING',
            'actual resume did not restore the same pinned distillation state');
        }
      }
      for (const [path, bytes] of independentBefore) {
        expect(readFileSync(join(actionRun, path)).equals(bytes),
          `${actionCase.action} mechanically mutated independent ${path}`);
      }
      pass(`${actionCase.action} is applied exactly once without S5/S6/S8 or relation conflation`);
    }

    const presentationRun = join(tempRoot, 'presentation-replacement');
    cpSync(authorityCheckpoint, presentationRun, { recursive: true });
    const presentationWriter = new LedgerWriter(presentationRun, CLOCK);
    const presentationQ2 = presentationWriter.openProceduralAuthorityFollowup({
      request_id: request.request_id,
      reason: 'presentation-only-replacement',
      next_subject: authoritySubject,
      presentation: false,
      required_authority_identity: 'human:fixture-operator',
      prepared_by: 'invocation:loa-orchestrator',
      requested_at: '2040-01-02T05:00:00.000Z',
    });
    expect(presentationQ2.presentation === null
      && presentationQ2.authority_subject_digest === request.authority_subject_digest,
    'presentation replacement changed the operative authority subject');
    expectThrows(
      () => recordHumanAuthorityDecision(presentationRun, {
        gateId: request.request_id,
        authorityIdentity: 'human:fixture-operator',
        decision: 'approve',
        recordedAt: '2040-01-02T05:01:00.000Z',
        simulation: { kind: 'fixture-simulated' },
        response: buildProceduralAuthorityResponse({
          request, request_bytes: requestBytes,
          authority_identity: 'human:fixture-operator', selected_action: 'carry-unresolved',
          observation: null, comment: null, recorded_at: '2040-01-02T05:01:00.000Z',
        }) as unknown as JsonValue,
      }),
      /not awaiting the named human authority gate/u,
      'stale Q1 response after presentation replacement',
    );
    pass('presentation-only replacement creates Q2 and makes unanswered Q1 stale');

    const materialRun = join(tempRoot, 'material-revision');
    cpSync(authorityCheckpoint, materialRun, { recursive: true });
    const revisedScope = structuredClone(operativeScope);
    revisedScope.impact_rows[0].consequence_if_unresolved = 'Re-reviewed explanatory consequence with unchanged typed treatment.';
    const materialSubjectM2: MaterialImpactSubject = {
      ...materialSubject,
      material_impact_seq: 2,
      operative_scope: revisedScope,
      proposed_by: 'invocation:material-impact-producer-0002',
    };
    const materialDigestM2 = materialImpactSubjectDigest(materialSubjectM2);
    const materialPathM2 = join(
      materialRun,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M2.json',
    );
    writeFileSync(materialPathM2, materialImpactSubjectJson(materialSubjectM2));
    const materialReviewM2 = join(
      materialRun,
      'verification/harness/S4-material-impact/VER-1692.md',
    );
    const materialReviewTextM2 = materialReviewText(
      'VER-1692',
      materialDigestM2,
      'upheld',
      'fixture revised Class C basis may be re-presented',
    );
    const authoritySubjectM2 = buildProceduralAuthoritySubject({
      ...authoritySubject,
      material_impact_seq: 2,
      material_impact_subject_ref: `material-impact-subject:AMB-1503:A1:M2@${materialDigestM2}`,
      material_impact_review_ref: `material-impact-verdict:VER-1692@${sha256Digest(materialReviewTextM2)}`,
      operative_scope: revisedScope,
    });
    const materialWriter = new LedgerWriter(materialRun, CLOCK);
    expectThrows(
      () => materialWriter.openProceduralAuthorityFollowup({
        request_id: request.request_id,
        reason: 'material-impact-revision',
        next_subject: authoritySubjectM2,
        presentation: true,
        required_authority_identity: 'human:fixture-operator',
        prepared_by: 'invocation:loa-orchestrator',
        requested_at: '2040-01-02T05:09:00.000Z',
      }),
      /review ref does not resolve to one exact retained verifier/u,
      'M2 request before material verifier',
    );
    expect(!existsSync(join(materialRun, 'control/gates/GATE-S4-AMB-1503-A1-Q2-request.json')),
      'M2-before-review interruption created Q2 prematurely');
    pass('crash matrix 9: retained M2 before review refuses Q2 until the exact upheld verifier exists');
    writeFileSync(materialReviewM2, materialReviewTextM2);
    const materialQ2 = materialWriter.openProceduralAuthorityFollowup({
      request_id: request.request_id,
      reason: 'material-impact-revision',
      next_subject: authoritySubjectM2,
      presentation: true,
      required_authority_identity: 'human:fixture-operator',
      prepared_by: 'invocation:loa-orchestrator',
      requested_at: '2040-01-02T05:10:00.000Z',
    });
    expect(materialQ2.request_id.endsWith('-Q2')
      && materialQ2.authority_subject.material_impact_seq === 2,
    'M2 material revision did not create exactly Q2');
    const materialResults = new ResultCollector(runId);
    runK2Ambiguities(materialResults, loadRun(materialRun), pinnedCoreAuthority);
    expect(materialResults.checks.find((check) => check.id === 'K2.17')?.status === 'PASS',
      `K2.17 rejected legal historical M1/Q1 plus active M2/Q2 retained state: ${
        materialResults.checks.filter((check) => check.status === 'FAIL')
          .map((check) => check.message).join('; ')
      }`);
    pass('material-impact M2 creates Q2 while preserving historical M1/Q1 and immutable T5.2/C1 bytes');

    const defectRun = join(tempRoot, 'material-defect-revision');
    cpSync(authorityCheckpoint, defectRun, { recursive: true });
    const defectScopeM2 = structuredClone(operativeScope);
    defectScopeM2.impact_rows[0].consequence_if_unresolved = 'Defective M2 explanatory basis under fresh challenge.';
    const defectSubjectM2: MaterialImpactSubject = {
      ...materialSubject,
      material_impact_seq: 2,
      operative_scope: defectScopeM2,
      proposed_by: 'invocation:material-impact-producer-defect',
    };
    const defectDigestM2 = materialImpactSubjectDigest(defectSubjectM2);
    writeFileSync(
      join(defectRun, 'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M2.json'),
      materialImpactSubjectJson(defectSubjectM2),
    );
    writeFileSync(
      join(defectRun, 'verification/harness/S4-material-impact/VER-1692.md'),
      materialReviewText('VER-1692', defectDigestM2, 'refuted', 'fixture M2 requires a new material subject'),
    );
    const defectResults = new ResultCollector(runId);
    runK2Ambiguities(defectResults, loadRun(defectRun), pinnedCoreAuthority);
    expect(defectResults.checks.find((check) => check.id === 'K2.17')?.status === 'FAIL',
      'refuted latest M2 did not block before a new material subject');
    const repairedScopeM3 = structuredClone(operativeScope);
    repairedScopeM3.impact_rows[0].consequence_if_unresolved = 'Fresh M3 reviewed consequence after the M2 defect.';
    const repairedSubjectM3: MaterialImpactSubject = {
      ...materialSubject,
      material_impact_seq: 3,
      operative_scope: repairedScopeM3,
      proposed_by: 'invocation:material-impact-producer-0003',
    };
    const repairedDigestM3 = materialImpactSubjectDigest(repairedSubjectM3);
    writeFileSync(
      join(defectRun, 'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M3.json'),
      materialImpactSubjectJson(repairedSubjectM3),
    );
    const repairedReviewM3 = materialReviewText(
      'VER-1693',
      repairedDigestM3,
      'upheld',
      'fixture M3 supersedes only the refuted material-impact proposal',
    );
    writeFileSync(
      join(defectRun, 'verification/harness/S4-material-impact/VER-1693.md'),
      repairedReviewM3,
    );
    const authoritySubjectM3 = buildProceduralAuthoritySubject({
      ...authoritySubject,
      material_impact_seq: 3,
      material_impact_subject_ref: `material-impact-subject:AMB-1503:A1:M3@${repairedDigestM3}`,
      material_impact_review_ref: `material-impact-verdict:VER-1693@${sha256Digest(repairedReviewM3)}`,
      operative_scope: repairedScopeM3,
    });
    const repairedQ2 = new LedgerWriter(defectRun, CLOCK).openProceduralAuthorityFollowup({
      request_id: request.request_id,
      reason: 'material-impact-revision',
      next_subject: authoritySubjectM3,
      presentation: true,
      required_authority_identity: 'human:fixture-operator',
      prepared_by: 'invocation:loa-orchestrator',
      requested_at: '2040-01-02T05:20:00.000Z',
    });
    expect(repairedQ2.request_id.endsWith('-Q2')
      && repairedQ2.authority_subject.material_impact_seq === 3,
    'refuted M2 recovery did not retain M3 while advancing only Q2');
    pass('crash matrix 8: material defect resumes with contiguous M3 and the next unused Q2');

    const response = buildProceduralAuthorityResponse({
      request,
      request_bytes: requestBytes,
      authority_identity: 'human:fixture-operator',
      selected_action: 'carry-unresolved',
      observation: null,
      comment: null,
      recorded_at: '2040-01-02T03:11:00.000Z',
    });
    recordHumanAuthorityDecision(runDir, {
      gateId: request.request_id,
      authorityIdentity: 'human:fixture-operator',
      decision: 'approve',
      recordedAt: response.recorded_at,
      simulation: { kind: 'fixture-simulated' },
      response: response as unknown as JsonValue,
    });
    const responsePending = readRunState(runDir);
    expect(responsePending.execution.halt?.code === 'S4_C2_RESPONSE_APPLICATION_REQUIRED',
      'retained response advanced run control before T5.3 application');
    expect(!readFileSync(ambiguityPath, 'utf8').includes('| AMB-1503 | 1 | 1 | carry-unresolved |'),
      'recording the response implicitly wrote T5.3');
    pass('response persistence halts before T5.3 and run-control application');
    pass('crash matrix 5: retained response before T5.3 remains halted for exact-once application');

    const observationToken = 'SLICE5-HUMAN-OBSERVATION-EXACT-BYTES-DO-NOT-EXPOSE';
    const observationPath = 'control/gates/withheld-human-observation.txt';
    writeFileSync(join(runDir, observationPath), observationToken);
    const roleCases: Array<{
      role: LoaRoleId;
      kind: 'producer' | 'refuter';
      allowlist: string[];
      producerContextId?: string;
    }> = [
      {
        role: 'ambiguity-producer',
        kind: 'producer',
        allowlist: ['corpus/sources/SRC-0401-source-walk.txt', 'ledgers/source-walk.md'],
      },
      {
        role: 'ambiguity-reviewer',
        kind: 'refuter',
        allowlist: ['corpus/sources/SRC-0401-source-walk.txt', 'ledgers/internal-ambiguities.md'],
        producerContextId: 'CTX-AMBIGUITY-PRODUCER-0001',
      },
      {
        role: 'material-impact-producer',
        kind: 'producer',
        allowlist: ['ledgers/internal-ambiguities.md', 'ledgers/relations.md'],
      },
      {
        role: 'material-impact-reviewer',
        kind: 'refuter',
        allowlist: ['ledgers/internal-ambiguities.md', 'ledgers/relations.md'],
        producerContextId: 'CTX-MATERIAL-IMPACT-PRODUCER-0001',
      },
    ];
    for (const [index, roleCase] of roleCases.entries()) {
      const assembled = assembleWorkerBundle({
        bundle,
        runDir,
        callId: `CALL-SLICE5-WITHHOLD-${String(index + 1).padStart(4, '0')}`,
        runId,
        stage: 'S4',
        role: roleCase.role,
        kind: roleCase.kind,
        allowlist: roleCase.allowlist,
        withheld: withheldInventory(bundle, runDir, roleCase.role, roleCase.allowlist),
        taskLine: 'Return only the exact bounded Slice 5 structured result.',
        modelIdentity: readRunState(runDir).identity.models[roleCase.role],
        producerContextId: roleCase.producerContextId,
      });
      const bundleBytes = Buffer.concat(walkRegularFiles(assembled.root).map((path) => readFileSync(path)));
      expect(!bundleBytes.includes(Buffer.from(observationToken, 'utf8')),
        `${roleCase.role} bundle exposed exact human observation bytes`);
      expect(!bundleBytes.includes(Buffer.from('human:fixture-operator', 'utf8')),
        `${roleCase.role} bundle exposed retained authority identity/response bytes`);
    }
    expectThrows(
      () => assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-SLICE5-WITHHOLD-ILLEGAL',
        runId,
        stage: 'S4',
        role: 'material-impact-producer',
        kind: 'producer',
        allowlist: [observationPath],
        withheld: withheldInventory(bundle, runDir, 'material-impact-producer', [observationPath]),
        taskLine: 'Return only the exact bounded Slice 5 structured result.',
        modelIdentity: readRunState(runDir).identity.models['material-impact-producer'],
      }),
      /may not expose adapter control state/u,
      'human observation allowlist injection',
    );
    pass('all four Slice 5 worker bundles withhold human response and observation bytes');

    const authorityReceipt = writer.appendProceduralAuthorityResponse(request.request_id);
    const authorityLedger = readFileSync(ambiguityPath, 'utf8');
    expect(authorityLedger.includes('| AMB-1503 | 1 | 1 | carry-unresolved | none |'),
      'exact Core-projected T5.3 row is absent');
    expect(readRunState(runDir).execution.halt === null,
      'progression-enabling response did not clear the application halt');
    pass('ambiguity/T5.3 append succeeds only after C1 and before progression');

    const replayedReceipt = writer.appendProceduralAuthorityResponse(request.request_id);
    expect(replayedReceipt.sequence === authorityReceipt.sequence
      && replayedReceipt.chain_digest === authorityReceipt.chain_digest
      && replayedReceipt.return_digest === authorityReceipt.return_digest,
      'idempotent response replay produced a different ledger receipt');
    expect(readFileSync(ambiguityPath, 'utf8').match(/\| AMB-1503 \| 1 \| 1 \| carry-unresolved \|/gu)?.length === 1,
      'idempotent response replay duplicated T5.3');
    pass('response/T5.3 application replay is exact-once and idempotent');

    const crashT53BeforeControl = join(tempRoot, 'crash-06-t53-before-control');
    cpSync(runDir, crashT53BeforeControl, { recursive: true });
    const ledgerTransactionPath = join(
      crashT53BeforeControl,
      'control/transactions',
      `TXN-ledger-${authorityReceipt.sequence}.json`,
    );
    const committedLedger = readJsonFile(ledgerTransactionPath) as Record<string, JsonValue>;
    const { committed_at: _committedLedgerAt, ...preparedLedger } = committedLedger;
    writeRunState(crashT53BeforeControl, responsePending);
    writeJsonAtomic(ledgerTransactionPath, { ...preparedLedger, status: 'prepared' });
    const recoveredLedger = recoverPendingLedgerTransactions(crashT53BeforeControl, CLOCK);
    expect(recoveredLedger.committed.some((entry) => entry.sequence === authorityReceipt.sequence)
      && readRunState(crashT53BeforeControl).execution.halt?.code === 'S4_C2_RESPONSE_APPLICATION_REQUIRED',
    'prepared T5.3 transaction did not recover without choosing or applying an action');
    const recoveredApplication = new LedgerWriter(crashT53BeforeControl, CLOCK)
      .appendProceduralAuthorityResponse(request.request_id);
    expect(recoveredApplication.sequence === authorityReceipt.sequence
      && readRunState(crashT53BeforeControl).execution.halt === null
      && readFileSync(join(crashT53BeforeControl, 'ledgers/internal-ambiguities.md'), 'utf8')
        .match(/\| AMB-1503 \| 1 \| 1 \| carry-unresolved \|/gu)?.length === 1,
    'T5.3-before-control recovery duplicated the row or failed to resume the first unmet action');
    pass('crash matrix 6: T5.3 before run-control advancement recovers without duplication or action invention');

    expectThrows(
      () => recordHumanAuthorityDecision(runDir, {
        gateId: request.request_id,
        authorityIdentity: 'human:fixture-operator',
        decision: 'approve',
        recordedAt: response.recorded_at,
        simulation: { kind: 'fixture-simulated' },
        response: response as unknown as JsonValue,
      }),
      /not awaiting the named human authority gate/u,
      'reused procedural response',
    );
    pass('one retained response cannot be reused as a second human action');

    writer.advanceSlice5ClosurePhase('S4-C2-ambiguities-finalized');
    expect(readFileSync(join(runDir, 'run-log.md'), 'utf8')
      .includes('closure_phase: S4-C2-ambiguities-finalized'), 'C2 marker was not retained');
    pass('C2 advances only after prospective K2.16 and K2.17 validation');
    pass('crash matrix 10: progression action before C2 resumes at the exact C2 marker without rerunning C1');

    const ambiguityAtC2 = readFileSync(ambiguityPath);
    expectThrows(
      () => writer.append('ledgers/internal-ambiguities.md', validated, () => '<!-- forbidden -->'),
      /canonical ambiguity append is legal only during the S4-C2 write window/u,
      'post-C2 ambiguity append',
    );
    expect(readFileSync(ambiguityPath).equals(ambiguityAtC2),
      'post-C2 ambiguity append changed bytes');
    pass('post-C2 ambiguity write is refused before bytes change');

    writer.advanceSlice5ClosurePhase('S4-C3-exit');
    const finalState = readRunState(runDir);
    expect(finalState.execution.stage === 'S4' && finalState.execution.stage_status === 'closed',
      'C3 did not close the retained S4 stage');
    expect(readFileSync(join(runDir, 'run-log.md'), 'utf8')
      .includes('closure_phase: S4-C3-exit'), 'C3 marker was not retained');
    pass('C3 closes S4 only after the complete C2 durable state');

    const preRecoveryStatus = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'status',
      runId,
    ]);
    const preRecoveryValidation = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'validate',
      runId,
    ]);
    expect(
      preRecoveryStatus.result === 'PASS'
        && preRecoveryValidation.result === 'PASS',
      'C3-before-S5 durable state was incoherent before recovery',
    );
    pass('C3-marker-before-S5-entry status and validation remain coherent');

    const c3MaterialSubjectPath = join(
      runDir,
      'verification/harness/S4/material-impact-subjects/AMB-1503-A1-M1.json',
    );
    const materialSubjectBytes = readFileSync(c3MaterialSubjectPath);
    rmSync(c3MaterialSubjectPath);
    const invalidResume = runFailingJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'resume',
      runId,
    ]);
    expect(
      invalidResume.result === 'FAIL'
        && (invalidResume.errors as JsonValue[]).some((error) => (
          typeof error === 'string' && /retained Core structural checks/iu.test(error)
        )),
      'C3 with invalid retained prerequisites did not fail closed',
    );
    writeFileSync(c3MaterialSubjectPath, materialSubjectBytes);
    pass('C3 marker with invalid retained prerequisites still fails closed');

    const runLogBeforeRecovery = readFileSync(join(runDir, 'run-log.md'), 'utf8');
    const relationsBeforeRecovery = readFileSync(relationPath);
    const recovered = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'resume',
      runId,
    ]);
    const recoveredState = readRunState(runDir);
    const recoveredLog = readFileSync(join(runDir, 'run-log.md'), 'utf8');
    const retainedS5Entry = firstRunLogEntry(loadRun(runDir).runLog, 'S5');
    const canonicalS5Entry = retainedS5Entry
      ? `## ${retainedS5Entry.timestamp} — S5 — ${retainedS5Entry.event}`
      : '';
    expect(
      recovered.result === 'PASS'
        && recoveredState.execution.stage === 'S5'
        && retainedS5Entry?.event === 'entry'
        && recoveredLog.split(/\r?\n/u).filter((line) => line === canonicalS5Entry).length === 1
        && !recoveredLog.split(/\r?\n/u).includes('stage_entry: S5')
        && (recoveredLog.match(/^closure_phase: S4-C1-relations-closed$/gmu) || []).length === 1
        && (recoveredLog.match(/^closure_phase: S4-C2-ambiguities-finalized$/gmu) || []).length === 1
        && (recoveredLog.match(/^closure_phase: S4-C3-exit$/gmu) || []).length === 1
        && readFileSync(relationPath).equals(relationsBeforeRecovery),
      'resume did not perform only the missing S5-entry transition',
    );
    expect(
      runLogBeforeRecovery !== recoveredLog
        && recoveredLog.startsWith(runLogBeforeRecovery),
      'S5 recovery rewrote retained run-log history',
    );
    expect(
      recoveredLog.includes(`${canonicalS5Entry}\n`)
        && !recoveredLog.slice(runLogBeforeRecovery.length).includes('\r'),
      'new S5 output must retain canonical em-dash and LF bytes',
    );
    pass('crash matrix 11: durable C3 before S5 entry resumes with only one S5 transition');
    pass('new S5 entry uses canonical em-dash and LF bytes');

    const postRecoveryStatus = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'status',
      runId,
    ]);
    const postRecoveryValidation = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'validate',
      runId,
    ]);
    expect(
      postRecoveryStatus.result === 'PASS'
        && postRecoveryValidation.result === 'PASS',
      'status and validation disagreed after S5 recovery',
    );
    const secondResume = runJsonProcess(runtimeCli, [
      '--json',
      '--root',
      loaRoot,
      'resume',
      runId,
    ]);
    const secondLog = readFileSync(join(runDir, 'run-log.md'), 'utf8');
    expect(
      secondResume.result === 'PASS'
        && secondLog === recoveredLog
        && readFileSync(relationPath).equals(relationsBeforeRecovery),
      'repeat resume duplicated S5 entry, closure markers, or relation state',
    );
    pass('crash matrix 12: repeated resume after recovered S5 entry is idempotent');
    pass('complete C3 with existing S5 entry never requests a nonexistent next closure phase');

    for (const heading of [
      {
        name: 'em-dash',
        value: canonicalS5Entry,
      },
      {
        name: 'ASCII-hyphen',
        value: `## ${retainedS5Entry?.timestamp || ''} - S5 - entry`,
      },
      {
        name: 'CRLF-em-dash',
        value: `${canonicalS5Entry}\r`,
      },
      {
        name: 'CRLF-ASCII-hyphen',
        value: `## ${retainedS5Entry?.timestamp || ''} - S5 - entry\r`,
      },
    ] as const) {
      const idempotentRun = join(tempRoot, `s5-${heading.name.toLowerCase()}-idempotency`);
      cpSync(runDir, idempotentRun, { recursive: true });
      const idempotentLogPath = join(idempotentRun, 'run-log.md');
      const idempotentLog = readFileSync(idempotentLogPath, 'utf8')
        .replace(canonicalS5Entry, heading.value);
      writeFileSync(idempotentLogPath, idempotentLog);
      const idempotentState = readRunState(idempotentRun);
      idempotentState.execution.stage = 'S4';
      idempotentState.execution.stage_status = 'closed';
      writeRunState(idempotentRun, idempotentState);
      enterS5InShippedRuntime(bundle.root, idempotentRun);
      expect(
        readFileSync(idempotentLogPath, 'utf8') === idempotentLog
          && hasRunLogEvent(loadRun(idempotentRun).runLog, 'S5', 'entry')
          && readRunState(idempotentRun).execution.stage === 'S5',
        `${heading.name} retained S5 entry was duplicated or not recognized`,
      );
      const withoutC3 = idempotentLog.replace('closure_phase: S4-C3-exit\n', '');
      expect(withoutC3 !== idempotentLog, 'idempotency case did not retain C3');
      writeFileSync(idempotentLogPath, withoutC3);
      const results = new ResultCollector(runId);
      runK2Ambiguities(results, loadRun(idempotentRun), pinnedCoreAuthority);
      expect(
        results.checks.some((check) => check.id === 'K2.17'
          && check.status === 'FAIL' && check.message.includes('S5 requires retained C3')),
        'K2.17 and shipped adapter disagree about the retained S5 entry',
      );
      pass(`${heading.name} retained S5 entry is shipped-adapter-idempotent and agrees with K2.17`);
    }

    const crlfHistoryRun = join(tempRoot, 's5-new-entry-after-crlf-history');
    cpSync(runDir, crlfHistoryRun, { recursive: true });
    const crlfHistoryPath = join(crlfHistoryRun, 'run-log.md');
    const crlfHistory = runLogBeforeRecovery.replace(/\n/g, '\r\n');
    writeFileSync(crlfHistoryPath, crlfHistory);
    const crlfHistoryState = readRunState(crlfHistoryRun);
    crlfHistoryState.execution.stage = 'S4';
    crlfHistoryState.execution.stage_status = 'closed';
    writeRunState(crlfHistoryRun, crlfHistoryState);
    enterS5InShippedRuntime(bundle.root, crlfHistoryRun);
    const crlfHistoryAfter = readFileSync(crlfHistoryPath, 'utf8');
    expect(
      crlfHistoryAfter.startsWith(crlfHistory)
        && crlfHistoryAfter.slice(crlfHistory.length).includes(`## ${FIXED_TIME} — S5 — entry\n`)
        && !crlfHistoryAfter.slice(crlfHistory.length).includes('\r'),
      'new S5 entry normalized retained CRLF history or mirrored its line endings',
    );
    pass('shipped S5 writer preserves CRLF history and appends canonical em-dash LF output');

    const recognizedResults = new ResultCollector(runId);
    runK2Ambiguities(recognizedResults, loadRun(runDir), pinnedCoreAuthority);
    expect(
      recognizedResults.checks.find((check) => check.id === 'K2.17')?.status === 'PASS',
      'K2.17 rejected the legal adapter-written canonical S5 entry',
    );
    pass('K2.17 recognizes the adapter-written canonical S5 entry');

    const closureMutationCases = [
      {
        name: 'C1',
        marker: 'closure_phase: S4-C1-relations-closed\n',
        diagnostic: 'C2, C3, and S5 require retained C1',
      },
      {
        name: 'C2',
        marker: 'closure_phase: S4-C2-ambiguities-finalized\n',
        diagnostic: 'C3 and S5 require retained C2',
      },
      {
        name: 'C3',
        marker: 'closure_phase: S4-C3-exit\n',
        diagnostic: 'S5 requires retained C3',
      },
    ] as const;
    for (const heading of [
      {
        name: 'em-dash',
        value: canonicalS5Entry,
      },
      {
        name: 'ASCII-hyphen',
        value: `## ${retainedS5Entry?.timestamp || ''} - S5 - entry`,
      },
      {
        name: 'CRLF-em-dash',
        value: `${canonicalS5Entry}\r`,
      },
      {
        name: 'CRLF-ASCII-hyphen',
        value: `## ${retainedS5Entry?.timestamp || ''} - S5 - entry\r`,
      },
    ] as const) {
      for (const mutation of closureMutationCases) {
        const mutatedRun = join(
          tempRoot,
          `s5-${heading.name.toLowerCase()}-missing-${mutation.name.toLowerCase()}`,
        );
        cpSync(runDir, mutatedRun, { recursive: true });
        const mutatedLogPath = join(mutatedRun, 'run-log.md');
        const beforeMutation = readFileSync(mutatedLogPath, 'utf8')
          .replace(canonicalS5Entry, heading.value);
        expect(
          beforeMutation.split(mutation.marker).length === 2,
          `${heading.name} ${mutation.name} mutation did not find exactly one retained marker`,
        );
        writeFileSync(mutatedLogPath, beforeMutation.replace(mutation.marker, ''));
        const checked = spawnSync(process.execPath, [
          join(bundle.root, 'runtime-js/scripts/validate-run.js'),
          '--root',
          bundle.root,
          '--run',
          mutatedRun,
          '--json',
        ], {
          encoding: 'utf8',
          maxBuffer: 64 * 1024 * 1024,
        });
        expect(
          !checked.error
            && checked.status !== 0
            && checked.stdout.includes(mutation.diagnostic),
          `pinned checker did not report ${mutation.diagnostic}: ${checked.stderr || checked.stdout}`,
        );
        pass(`${heading.name} S5 entry with missing ${mutation.name} fails K2.17`);
      }
    }

    const legacyRun = join(tempRoot, 's5-legacy-private-token');
    cpSync(runDir, legacyRun, { recursive: true });
    const legacyLogPath = join(legacyRun, 'run-log.md');
    const legacyBefore = readFileSync(legacyLogPath, 'utf8');
    expect(
      legacyBefore.split(`${canonicalS5Entry}\n`).length === 2,
      'legacy-token mutation did not find exactly one canonical S5 entry',
    );
    writeFileSync(
      legacyLogPath,
      legacyBefore
        .replace(`${canonicalS5Entry}\n`, 'stage_entry: S5\n')
        .replace('closure_phase: S4-C3-exit\n', ''),
    );
    const legacyResults = new ResultCollector(runId);
    runK2Ambiguities(legacyResults, loadRun(legacyRun), pinnedCoreAuthority);
    expect(
      legacyResults.checks.find((check) => check.id === 'K2.17')?.status === 'PASS',
      'adapter-private stage_entry token was treated as a Core S5 entry',
    );
    pass('adapter-private stage_entry: S5 does not satisfy Core S5-entry recognition');

    console.log(`RESULT: PASS (${CASES.length}/${CASES.length} process cases)`);
  } finally {
    makeWritable(tempRoot);
    rmSync(tempRoot, { recursive: true, force: true });
    if (existsSync(bundleOutput)) {
      makeWritable(bundleOutput);
      rmSync(bundleOutput, { recursive: true, force: true });
    }
  }
}

main();
