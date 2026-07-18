#!/usr/bin/env node

import type { SpawnSyncReturns } from 'node:child_process';
import {
  chmodSync,
  copyFileSync,
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
import { Worker } from 'node:worker_threads';
import {
  dirname,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assembleBundles,
  verifyBundle,
} from '../../../scripts/assemble-bundles.ts';
import {
  dispatchLoaCommand,
  recordS0AuthorityResponse,
  recoverPendingS0Transaction,
} from '../src/cli.ts';
import {
  invokePinnedChecker,
  type CheckerSpawn,
} from '../src/checker.ts';
import {
  readLockedFile,
  readVerifiedBundleLock,
  verifyAndLoadLoaBundle,
  type VerifiedLoaBundle,
} from '../src/core-loader.ts';
import {
  readJsonFile,
  sha256Digest,
  stableJson,
  stableJsonBytes,
  walkRegularFiles,
  writeJsonAtomic,
} from '../src/fs.ts';
import {
  installLoaBundle,
  resealLoaInstallLock,
  verifyLoaInstallation,
} from '../src/installer.ts';
import type { LoaInstallLock } from '../src/installer.ts';
import {
  runInstalledLauncher,
  verifyInstalledLauncherRuntime,
} from '../src/launcher.ts';
import { verifyCorpusSnapshot } from '../src/intake.ts';
import { runLoaPreflight } from '../src/preflight.ts';
import {
  LedgerWriter,
  recoverPendingLedgerTransactions,
} from '../src/ledger-writer.ts';
import {
  openHumanAuthorityGate,
  readRunState,
  recordHumanAuthorityDecision,
  recoverPendingAuthorityTransactions,
  runDirectory,
  runtimeSnapshotPath,
  updateRunState,
  writeRunState,
} from '../src/run-control.ts';
import {
  verifyRuntimeSnapshot,
} from '../src/runtime-snapshot.ts';
import {
  LOA_BUNDLE_ID,
  LOA_INSTALLED_BUNDLE_ROOT,
  LOA_INSTALL_LOCK_PATH,
  type CoreStage,
  type Clock,
  type CorpusSnapshot,
  type IdSource,
  type JsonValue,
  type LedgerReceipt,
  type LoaHostCapabilities,
  type LoaRoleId,
  type LoaRunState,
  type RuntimeSnapshot,
  type S0AuthorityResponse,
  type WorkerDispatchReceipt,
  type WorkerRequest,
} from '../src/types.ts';
import {
  assembleWorkerBundle,
  coreBlindPolicyReference,
  verifyWorkerBundle,
} from '../src/worker-bundle.ts';
import {
  acceptLoaWorkerHandoff,
  dispatchLoaWorker,
  prepareLoaWorkerHandoff,
} from '../src/worker-dispatch.ts';
import {
  ValidatedWorkerReturn,
  validateWorkerDispatch,
  validateWorkerReturn,
} from '../src/worker-return.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '../../..');
const FIXTURE_ROOT = join(REPO_ROOT, 'adapters', 'loa', 'tests', 'fixtures');
const RUN_ID = 'RUN-SYNTHETIC-LOA-001';
const FIXED_TIME = '2040-01-02T03:04:05.000Z';

const INSTALL_EXPOSURES = [
  {
    source: 'adapters/loa/command/loa-aleph.md',
    destination: '.claude/commands/loa-aleph.md',
  },
  {
    source: 'adapters/loa/skill/loa-aleph/SKILL.md',
    destination: '.claude/skills/loa-aleph/SKILL.md',
  },
  {
    source: 'runtime-js/adapters/loa/src/launcher.js',
    destination: '.claude/aleph/bin/loa-aleph.mjs',
  },
] as const;

interface AdapterCaseResult {
  name: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

export interface LoaAdapterTestReport {
  result: 'PASS' | 'FAIL';
  fixture: 'fixture-simulated';
  real_model_calls: 'none';
  cases: AdapterCaseResult[];
}

interface AdapterTestContext {
  tempRoot: string;
  selectedBundle: string;
  loaRoot: string;
  capabilitiesPath: string;
  inputA: string;
  inputDirectory: string;
  sourceABytes: Buffer;
  sourceBBytes: Buffer;
  runDir: string | null;
  stagedCorpus: CorpusSnapshot | null;
  ledgerRecovery: LedgerRecoveryFixture | null;
}

interface LedgerRecoveryFixture {
  runDir: string;
  relativePath: string;
  validated: ValidatedWorkerReturn<JsonValue>;
  stateBefore: LoaRunState;
  targetBefore: Buffer | null;
  chainBefore: Buffer | null;
  receipt: LedgerReceipt;
  targetAfter: Buffer;
  chainAfter: Buffer;
  transactionPath: string;
  committedJournal: Record<string, unknown>;
}

const CLOCK: Clock = { now: () => FIXED_TIME };
const IDS: IdSource = {
  nextRunId: () => RUN_ID,
  nextCallId: (_runId: string) => 'CALL-SYNTHETIC-0001',
};

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function expectThrows(
  operation: () => unknown,
  pattern: RegExp,
  label: string,
): void {
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

function runCase(
  results: AdapterCaseResult[],
  name: string,
  operation: () => void,
): void {
  try {
    operation();
    results.push({ name, status: 'PASS' });
  } catch (error) {
    results.push({
      name,
      status: 'FAIL',
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function runAsyncCase(
  results: AdapterCaseResult[],
  name: string,
  operation: () => Promise<void>,
): Promise<void> {
  try {
    await operation();
    results.push({ name, status: 'PASS' });
  } catch (error) {
    results.push({
      name,
      status: 'FAIL',
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

function runConcurrentValidateWorker(
  cliPath: string,
  loaRoot: string,
  runId: string,
  barrier: SharedArrayBuffer,
): Promise<{ status: number; output: string[] }> {
  return new Promise((resolvePromise, rejectPromise) => {
    const worker = new Worker(`
      const { parentPort, workerData } = require('node:worker_threads');
      void import(workerData.cliPath).then(({ validateLoaRun }) => {
        const barrier = new Int32Array(workerData.barrier);
        const result = validateLoaRun(workerData.runId, {
          loaRoot: workerData.loaRoot,
          allowSimulation: true,
          clock: { now: () => workerData.now },
          checkerSpawn: () => {
            const arrivals = Atomics.add(barrier, 0, 1) + 1;
            if (arrivals < 2) {
              while (Atomics.load(barrier, 0) < 2) {
                Atomics.wait(barrier, 0, 1, 10_000);
              }
            } else {
              Atomics.notify(barrier, 0);
            }
            return {
              pid: 4244,
              output: [null, '{"result":"FAIL","fixture":"concurrent"}\\n', ''],
              stdout: '{"result":"FAIL","fixture":"concurrent"}\\n',
              stderr: '',
              status: 1,
              signal: null,
            };
          },
        });
        parentPort.postMessage({
          status: result.result === 'FAIL' ? 1 : 0,
          output: [JSON.stringify(result)],
        });
      }, (error) => {
        parentPort.postMessage({ error: error instanceof Error ? error.message : String(error) });
      });
    `, {
      eval: true,
      workerData: { cliPath, loaRoot, runId, barrier, now: FIXED_TIME },
    });
    worker.once('error', rejectPromise);
    worker.once('message', (message: { status?: number; output?: string[]; error?: string }) => {
      if (message.error || message.status === undefined) {
        rejectPromise(new Error(message.error || 'validate worker returned no status'));
      } else {
        resolvePromise({ status: message.status, output: message.output || [] });
      }
    });
  });
}

function makeTreeWritable(path: string): void {
  if (!existsSync(path)) return;
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) return;
  if (stat.isDirectory()) {
    chmodSync(path, 0o700);
    for (const name of readdirSync(path)) makeTreeWritable(join(path, name));
  } else {
    chmodSync(path, 0o600);
  }
}

function copyFixture(source: string, destination: string): Buffer {
  mkdirSync(dirname(destination), { recursive: true });
  copyFileSync(source, destination);
  return readFileSync(destination);
}

function installedBundleRoot(loaRoot: string): string {
  return join(loaRoot, LOA_INSTALLED_BUNDLE_ROOT);
}

function readRuntime(runDir: string): RuntimeSnapshot {
  return readJsonFile(runtimeSnapshotPath(runDir)) as RuntimeSnapshot;
}

function exactWithheldInventory(
  bundle: VerifiedLoaBundle,
  runDir: string,
  role: Parameters<typeof coreBlindPolicyReference>[1],
  stage: Parameters<typeof coreBlindPolicyReference>[2],
  allowlist: string[],
) {
  const allowed = new Set(allowlist);
  const coreRef = coreBlindPolicyReference(bundle, role, stage);
  return walkRegularFiles(runDir)
    .map((path) => relative(runDir, path).split(sep).join('/'))
    .filter((path) => !path.startsWith('control/') && !allowed.has(path))
    .sort((left, right) => left.localeCompare(right))
    .map((selector) => ({ selector, core_ref: coreRef }));
}

function fixtureDispatchReceipt(
  request: WorkerRequest,
  contextId: string,
  producerContextId: string | null = request.isolation.producer_context_id,
): WorkerDispatchReceipt {
  return {
    format: 'aleph-loa-worker-dispatch/v1',
    call_id: request.call_id,
    context_id: contextId,
    producer_context_id: producerContextId,
    fresh_context: true,
    inherited_context: false,
    filesystem: 'bundle-read-only',
    model_identity: request.model_identity,
    simulation: { kind: 'fixture-simulated' },
  };
}

function fixtureAuthorityResponse(corpus: CorpusSnapshot): S0AuthorityResponse {
  return {
    format: 'aleph-loa-authority-response/v1',
    gate_id: 'S0',
    run_id: corpus.run_id,
    authority: {
      kind: 'human',
      identity: 'fixture-simulated-human-authority',
    },
    decision: 'approve-freeze',
    declared_scope: 'Fixture-simulated structural intake of the two exact test sources.',
    exclusions: [],
    sensitivity_rulings: corpus.files.map((file) => ({
      source_id: file.source_id,
      labels: ['none'],
      decision: 'admit-exact-bytes',
    })),
    freeze: true,
    recorded_at: '2040-01-02T03:05:00.000Z',
    simulation: { kind: 'fixture-simulated' },
  };
}

function prepareContext(tempRoot: string): AdapterTestContext {
  const assembledRoot = join(tempRoot, 'assembled');
  const assembly = assembleBundles(REPO_ROOT, assembledRoot);
  expect(assembly.result === 'PASS', `bundle assembly failed: ${assembly.errors.join('; ')}`);
  const selected = assembly.bundles.find((bundle) => bundle.id === LOA_BUNDLE_ID);
  expect(selected !== undefined, `bundle assembly omitted ${LOA_BUNDLE_ID}`);
  const verified = verifyBundle(selected.path);
  expect(
    verified.result === 'PASS' && verified.summary?.id === LOA_BUNDLE_ID,
    `assembled Loa bundle failed verification: ${verified.errors.join('; ')}`,
  );

  const loaRoot = join(tempRoot, 'synthetic-loa-host');
  const installation = installLoaBundle(selected.path, loaRoot);
  expect(
    installation.result === 'PASS',
    `fixture installation failed: ${installation.errors.join('; ')}`,
  );
  const installationVerification = verifyLoaInstallation(loaRoot);
  expect(
    installationVerification.result === 'PASS',
    `fixture installation did not verify: ${installationVerification.errors.join('; ')}`,
  );

  const capabilitiesPath = join(loaRoot, 'grimoires', 'loa', 'aleph', 'host-capabilities.json');
  copyFixture(join(FIXTURE_ROOT, 'host-capabilities.json'), capabilitiesPath);
  const inputA = join(loaRoot, 'fixture-input', 'source-a.md');
  const inputDirectory = join(loaRoot, 'fixture-input', 'nested');
  const sourceABytes = copyFixture(
    join(FIXTURE_ROOT, 'corpus', 'source-a.md'),
    inputA,
  );
  const sourceBBytes = copyFixture(
    join(FIXTURE_ROOT, 'corpus', 'nested', 'source-b.txt'),
    join(inputDirectory, 'source-b.txt'),
  );
  return {
    tempRoot,
    selectedBundle: selected.path,
    loaRoot,
    capabilitiesPath,
    inputA,
    inputDirectory,
    sourceABytes,
    sourceBBytes,
    runDir: null,
    stagedCorpus: null,
    ledgerRecovery: null,
  };
}

function startOptions(context: AdapterTestContext) {
  return {
    loaRoot: context.loaRoot,
    allowSimulation: true,
    clock: CLOCK,
    idSource: IDS,
  } as const;
}

function requireRun(context: AdapterTestContext): {
  runDir: string;
  corpus: CorpusSnapshot;
  state: LoaRunState;
} {
  expect(context.runDir !== null, 'synthetic run was not created');
  expect(context.stagedCorpus !== null, 'synthetic corpus was not staged');
  return {
    runDir: context.runDir,
    corpus: context.stagedCorpus,
    state: readRunState(context.runDir),
  };
}

function assertFixtureBoundary(state: LoaRunState, runDir: string): void {
  expect(state.full_mode === 'fixture-simulated', 'simulated host was labeled full live Aleph');
  expect(
    !['ACCEPTED', 'PROJECTION-ACCEPTED'].includes(state.execution.core_state),
    'fixture-simulated run reached an acceptance state',
  );
  const manifest = readFileSync(join(runDir, 'run-manifest.md'), 'utf8');
  expect(manifest.includes('fixture-simulated'), 'run manifest omits fixture-simulated label');
  expect(
    /not (?:replay|validation|acceptance|sanction)/u.test(manifest)
      || manifest.includes('not replay, validation, acceptance, or sanction evidence'),
    'run manifest omits the non-evidence boundary',
  );
  const runtime = readRuntime(runDir);
  expect(
    runtime.host.simulation?.kind === 'fixture-simulated',
    'runtime snapshot lost its fixture-simulated host label',
  );
}

export async function runLoaAdapterTests(): Promise<LoaAdapterTestReport> {
  const results: AdapterCaseResult[] = [];
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-loa-adapter-tests-'));
  try {
    let context: AdapterTestContext;
    try {
      context = prepareContext(tempRoot);
      results.push({
        name: 'offline aleph-for-loa assembly and synthetic host installation',
        status: 'PASS',
      });
    } catch (error) {
      results.push({
        name: 'offline aleph-for-loa assembly and synthetic host installation',
        status: 'FAIL',
        error: error instanceof Error ? error.message : String(error),
      });
      return {
        result: 'FAIL',
        fixture: 'fixture-simulated',
        real_model_calls: 'none',
        cases: results,
      };
    }

    runCase(results, 'verified bundle consumers retain the exact stable bytes they hash', () => {
      const bundle = verifyAndLoadLoaBundle(context.selectedBundle);
      const record = bundle.lock.files.find((file) => file.classification === 'core');
      expect(record !== undefined, 'fixture bundle contains no Core file');
      const filePath = join(bundle.root, record.path);
      const lockPath = join(bundle.root, 'bundle.lock.json');
      const originalFile = readFileSync(filePath);
      const originalLock = readFileSync(lockPath);
      const fileMode = lstatSync(filePath).mode & 0o777;
      const lockMode = lstatSync(lockPath).mode & 0o777;
      try {
        chmodSync(filePath, 0o600);
        chmodSync(lockPath, 0o600);
        writeFileSync(filePath, 'post-verification substituted payload\n');
        writeFileSync(lockPath, '{}\n');
        expect(
          readLockedFile(bundle, record.path, record.classification).equals(originalFile),
          'locked-file consumer reread substituted post-verification bytes',
        );
        expect(
          readVerifiedBundleLock(bundle).equals(originalLock),
          'bundle-lock consumer reread a substituted post-verification lock',
        );
        const callerCopy = readLockedFile(bundle, record.path);
        callerCopy.fill(0);
        expect(
          readLockedFile(bundle, record.path).equals(originalFile),
          'caller mutation changed retained verified bytes',
        );
      } finally {
        writeFileSync(filePath, originalFile);
        writeFileSync(lockPath, originalLock);
        chmodSync(filePath, fileMode);
        chmodSync(lockPath, lockMode);
      }
      expect(
        verifyBundle(context.selectedBundle).result === 'PASS',
        'bundle fixture did not verify after exact-byte regression restoration',
      );
    });

    runCase(results, 'command skill launcher and complete installed runtime paths resolve', () => {
      expect(existsSync(join(context.loaRoot, LOA_INSTALL_LOCK_PATH)), 'install receipt is missing');
      const runtimeRoot = installedBundleRoot(context.loaRoot);
      for (const exposure of INSTALL_EXPOSURES) {
        const source = join(runtimeRoot, exposure.source);
        const destination = join(context.loaRoot, exposure.destination);
        expect(existsSync(source), `installed bundle source is missing: ${exposure.source}`);
        expect(existsSync(destination), `host exposure is missing: ${exposure.destination}`);
        expect(
          readFileSync(destination).equals(readFileSync(source)),
          `host exposure differs from immutable source: ${exposure.destination}`,
        );
      }
      const command = readFileSync(join(context.loaRoot, INSTALL_EXPOSURES[0].destination), 'utf8');
      for (const syntax of [
        'start <files-or-directories...>',
        'status [RUN-id]',
        'resume <RUN-id>',
        'validate <RUN-id>',
      ]) {
        expect(command.includes(syntax), `slash command omits ${syntax}`);
      }
      const skill = readFileSync(join(context.loaRoot, INSTALL_EXPOSURES[1].destination), 'utf8');
      expect(skill.includes('.claude/aleph/bin/loa-aleph.mjs'), 'skill does not resolve launcher');
      expect(skill.includes('fixture-simulated'), 'skill omits simulation evidence boundary');
    });

    runCase(results, 'unresolved model identity fails before run creation without degraded mode', () => {
      const badPath = join(context.loaRoot, 'fixture-input', 'unresolved-host.json');
      const bad = JSON.parse(readFileSync(context.capabilitiesPath, 'utf8')) as LoaHostCapabilities;
      bad.models.judgment.model_id = 'latest';
      writeFileSync(badPath, `${JSON.stringify(bad, null, 2)}\n`);
      const before = existsSync(join(context.loaRoot, 'grimoires', 'loa', 'aleph', 'runs'))
        ? readdirSync(join(context.loaRoot, 'grimoires', 'loa', 'aleph', 'runs')).length
        : 0;
      const rejected = dispatchLoaCommand(
        ['start', relative(context.loaRoot, context.inputA)],
        {
          ...startOptions(context),
          capabilitiesPath: badPath,
          idSource: { ...IDS, nextRunId: () => 'RUN-UNRESOLVED-MODEL' },
        },
      );
      expect(rejected.result === 'FAIL', 'unresolved model identity unexpectedly started');
      expect(rejected.full_mode === 'not-started', 'failed preflight was relabeled full mode');
      expect(
        rejected.errors.some((error) => /mutable|unresolved|alias/iu.test(error)),
        `unresolved identity failure lacks exact diagnostic: ${rejected.errors.join('; ')}`,
      );
      const after = existsSync(join(context.loaRoot, 'grimoires', 'loa', 'aleph', 'runs'))
        ? readdirSync(join(context.loaRoot, 'grimoires', 'loa', 'aleph', 'runs')).length
        : 0;
      expect(after === before, 'failed model preflight left a run directory');

      const mismatchedPath = join(context.loaRoot, 'fixture-input', 'mismatched-host.json');
      const mismatched = JSON.parse(
        readFileSync(context.capabilitiesPath, 'utf8'),
      ) as LoaHostCapabilities;
      mismatched.models.judgment.effort = 'low';
      writeFileSync(mismatchedPath, `${JSON.stringify(mismatched, null, 2)}\n`);
      const preflight = runLoaPreflight({
        root: REPO_ROOT,
        capabilities: mismatchedPath,
      });
      expect(preflight.result === 'FAIL', 'standalone preflight accepted mismatched role mechanics');
      expect(
        preflight.checks.some((check) => (
          check.id === 'LP8'
          && check.status === 'FAIL'
          && check.problems.some((problem) => /does not match exact host slot/iu.test(problem))
        )),
        'standalone preflight did not report the exact role-mechanics mismatch',
      );
    });

    runCase(results, 'start status resume and validate dispatch persist the S0 human halt', () => {
      const started = dispatchLoaCommand(
        [
          'start',
          relative(context.loaRoot, context.inputA),
          relative(context.loaRoot, context.inputDirectory),
        ],
        startOptions(context),
      );
      expect(started.result === 'BLOCKED', `start did not stop at S0: ${stableJson(started)}`);
      expect(started.run_id === RUN_ID, 'start returned the wrong run ID');
      expect(started.state === 'BLOCKED' && started.stage === 'S0', 'start state is not blocked S0');
      expect(started.gate?.status === 'awaiting-authority', 'S0 gate is not awaiting authority');
      context.runDir = runDirectory(context.loaRoot, RUN_ID);
      context.stagedCorpus = verifyCorpusSnapshot(context.runDir);

      const status = dispatchLoaCommand(['status', RUN_ID], startOptions(context));
      expect(status.result === 'BLOCKED', 'status did not preserve the human halt');
      const listed = dispatchLoaCommand(['status'], startOptions(context));
      expect(listed.result === 'PASS', 'status list dispatch failed');
      expect(stableJson(listed.details).includes(RUN_ID), 'status list omitted the run');
      const resumed = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(resumed.result === 'BLOCKED', 'resume crossed an unanswered human gate');
      expect(
        readdirSync(join(context.runDir, 'control', 'worker-bundles')).length === 0,
        'a worker was dispatched before the S0 human gate',
      );
      const pinnedBefore = readRunState(context.runDir);
      expectThrows(
        () => updateRunState(context.runDir as string, FIXED_TIME, (draft) => {
          draft.identity.run_format_version = 'mutated-run-format';
        }),
        /mutate pinned run identity/iu,
        'run-format identity mutation',
      );
      expect(
        stableJson(readRunState(context.runDir)) === stableJson(pinnedBefore),
        'rejected identity mutation changed durable run state',
      );

      let checkerCalls = 0;
      const checkerSpawn: CheckerSpawn = (executable, args, cwd) => {
        checkerCalls += 1;
        const runtime = readRuntime(context.runDir as string);
        expect(executable === process.execPath, 'validate used an unpinned executable');
        const checkerInvocationRoot = resolve(dirname(args[0]), '..', '..');
        expect(
          checkerInvocationRoot.startsWith(join(
            context.runDir as string,
            'control',
            'checker-invocations',
            'CHECKER-',
          )),
          'validate did not use a private retained checker invocation',
        );
        expect(
          readFileSync(args[0]).equals(readFileSync(join(
            runtime.bundle.root,
            'runtime-js',
            'scripts',
            'validate-run.js',
          ))),
          'retained checker invocation differs from the run-local verified checker',
        );
        expect(args.includes('--root') && args.includes(runtime.bundle.root), 'validate omitted pinned Core root');
        expect(args.includes('--run') && args.includes(context.runDir as string), 'validate omitted run path');
        expect(cwd === checkerInvocationRoot, 'validate used a mutable working directory');
        return {
          pid: 4242,
          output: [null, '{"result":"FAIL","fixture":"incomplete-S0"}\n', ''],
          stdout: '{"result":"FAIL","fixture":"incomplete-S0"}\n',
          stderr: '',
          status: 1,
          signal: null,
        } as SpawnSyncReturns<string>;
      };
      const checked = dispatchLoaCommand(
        ['validate', RUN_ID],
        { ...startOptions(context), checkerSpawn },
      );
      expect(checked.result === 'FAIL', 'incomplete S0 fixture unexpectedly conformed');
      expect(checkerCalls === 1, 'validate dispatch did not invoke exactly one checker');
      expect(
        existsSync(join(context.runDir, 'control', 'checks', 'CHECK-0001.json')),
        'validate did not persist its exact check record',
      );
      expect(
        existsSync(join(context.runDir, 'verification', 'kernel-report.md')),
        'validate did not render the pinned Core kernel report',
      );
      assertFixtureBoundary(readRunState(context.runDir), context.runDir);
    });

    runCase(results, 'checker publication recovers a prepared result before the next invocation', () => {
      const { runDir } = requireRun(context);
      const transactionPath = join(
        runDir,
        'control',
        'transactions',
        'TXN-checker-0001.json',
      );
      const committed = readJsonFile(transactionPath) as Record<string, JsonValue>;
      expect(committed.status === 'committed', 'initial checker transaction was not committed');
      expect(typeof committed.record_path === 'string', 'checker journal omitted its record path');
      expect(
        typeof committed.kernel_report_path === 'string',
        'checker journal omitted its kernel report path',
      );
      const recordPath = join(runDir, committed.record_path);
      const kernelReportPath = join(runDir, committed.kernel_report_path);
      const expectedRecord = readFileSync(recordPath);
      const expectedReport = readFileSync(kernelReportPath);
      rmSync(recordPath);
      rmSync(kernelReportPath);
      writeJsonAtomic(transactionPath, {
        ...committed,
        status: 'prepared',
        committed_at: null,
      });
      let recoveredBeforeSpawn = false;
      const checked = invokePinnedChecker({
        runDir,
        clock: CLOCK,
        allowSimulation: true,
        spawn: () => {
          recoveredBeforeSpawn = existsSync(recordPath) && existsSync(kernelReportPath);
          return {
            pid: 4243,
            output: [null, '{"result":"FAIL","fixture":"recovery-followup"}\n', ''],
            stdout: '{"result":"FAIL","fixture":"recovery-followup"}\n',
            stderr: '',
            status: 1,
            signal: null,
          } as SpawnSyncReturns<string>;
        },
      });
      expect(recoveredBeforeSpawn, 'prepared checker result was not recovered before checker execution');
      expect(readFileSync(recordPath).equals(expectedRecord), 'checker recovery changed record bytes');
      expect(readFileSync(kernelReportPath).equals(expectedReport), 'checker recovery changed report bytes');
      expect(
        (readJsonFile(transactionPath) as Record<string, JsonValue>).status === 'committed',
        'recovered checker journal was not committed',
      );
      expect(
        checked.recordPath.endsWith('CHECK-0002.json')
          && checked.kernelReportPath.endsWith('kernel-report-2.md'),
        'follow-up checker invocation reused a recovered result slot',
      );
    });

    runCase(results, 'multi-source intake is byte-exact frozen and S0 recovery is crash-consistent', () => {
      const { runDir, corpus } = requireRun(context);
      const stateBeforeS0 = structuredClone(readRunState(runDir));
      const filesBeforeS0 = {
        runManifest: readFileSync(join(runDir, 'run-manifest.md')),
        runLog: readFileSync(join(runDir, 'run-log.md')),
        corpusManifest: readFileSync(join(runDir, 'corpus', 'manifest.md')),
      };
      expect(corpus.files.length === 2, `intake captured ${String(corpus.files.length)} files`);
      const records = [...corpus.files].sort((left, right) => left.source_id.localeCompare(right.source_id));
      expect(readFileSync(join(runDir, records[0].frozen_path)).equals(context.sourceABytes), 'source A frozen bytes differ');
      expect(readFileSync(join(runDir, records[1].frozen_path)).equals(context.sourceBBytes), 'nested source B frozen bytes differ');
      expect(records[1].relative_path === 'source-b.txt', 'nested directory intake lost the source-local path');
      expect(records[0].digest === sha256Digest(context.sourceABytes), 'source A inventory hash is wrong');
      expect(records[1].digest === sha256Digest(context.sourceBBytes), 'source B inventory hash is wrong');

      writeFileSync(context.inputA, 'mutated after staging\n');
      writeFileSync(join(context.inputDirectory, 'source-b.txt'), 'also mutated after staging\n');
      const stillStaged = verifyCorpusSnapshot(runDir);
      expect(readFileSync(join(runDir, records[0].frozen_path)).equals(context.sourceABytes), 'source A followed mutable origin');
      expect(readFileSync(join(runDir, records[1].frozen_path)).equals(context.sourceBBytes), 'source B followed mutable origin');

      const response = fixtureAuthorityResponse(stillStaged);
      const approved = recordS0AuthorityResponse(RUN_ID, response, startOptions(context));
      expect(approved.result === 'PASS', `fixture S0 response failed: ${approved.errors.join('; ')}`);
      const s0TransactionPath = join(
        runDir,
        'control',
        'transactions',
        'TXN-s0-freeze.json',
      );
      const committedS0 = readJsonFile(s0TransactionPath) as Record<string, JsonValue>;
      const s0Plan = committedS0.plan as Record<string, JsonValue>;
      const { committed_at: _s0CommittedAt, ...preparedS0 } = committedS0;
      writeRunState(runDir, stateBeforeS0);
      writeJsonAtomic(join(runDir, 'control', 'corpus.snapshot.json'), s0Plan.staged);
      rmSync(join(runDir, 'control', 'gates', 'GATE-S0-response.json'));
      writeFileSync(join(runDir, 'run-manifest.md'), filesBeforeS0.runManifest);
      writeFileSync(join(runDir, 'run-log.md'), filesBeforeS0.runLog);
      writeFileSync(join(runDir, 'corpus', 'manifest.md'), filesBeforeS0.corpusManifest);
      writeJsonAtomic(s0TransactionPath, { ...preparedS0, status: 'prepared' });
      const recoveredS0 = recoverPendingS0Transaction(runDir, {
        now: () => '2040-01-02T03:05:30.000Z',
      });
      expect(recoveredS0?.corpus.state === 'frozen', 'prepared S0 freeze did not recover');
      expect(
        (readJsonFile(s0TransactionPath) as Record<string, JsonValue>).status === 'committed',
        'recovered S0 transaction was not committed',
      );
      const frozen = verifyCorpusSnapshot(runDir);
      expect(frozen.status === 'frozen', 'authority-approved corpus did not freeze');
      for (const file of frozen.files) {
        expect(
          (lstatSync(join(runDir, file.frozen_path)).mode & 0o222) === 0,
          `frozen source remains writable: ${file.frozen_path}`,
        );
      }
      const resumed = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(resumed.result === 'PASS', `resume after S0 freeze failed: ${resumed.errors.join('; ')}`);
      const state = readRunState(runDir);
      expect(state.execution.core_state === 'CORPUS-FROZEN', 'S0 response advanced beyond corpus freeze');
      expect(state.execution.gate?.status === 'approved', 'S0 response was not durably recorded');
      assertFixtureBoundary(state, runDir);
    });

    await runAsyncCase(results, 'installed launcher dynamically dispatches all four command operations', async () => {
      const captured: string[] = [];
      const priorLog = console.log;
      const priorError = console.error;
      console.log = (...values: unknown[]) => { captured.push(values.map(String).join(' ')); };
      console.error = (...values: unknown[]) => { captured.push(values.map(String).join(' ')); };
      try {
        const common = [
          '--json',
          '--root',
          context.loaRoot,
          '--capabilities',
          context.capabilitiesPath,
          '--allow-fixture-simulation',
        ];
        const statuses = [
          await runInstalledLauncher(context.loaRoot, [...common, 'start', 'missing-fixture-source.md']),
          await runInstalledLauncher(context.loaRoot, [...common, 'status', RUN_ID]),
          await runInstalledLauncher(context.loaRoot, [...common, 'resume', RUN_ID]),
          await runInstalledLauncher(context.loaRoot, [...common, 'validate', RUN_ID]),
        ];
        expect(statuses[0] === 1, 'installed start did not dispatch its fail-closed input check');
        expect(statuses[1] === 0 && statuses[2] === 0, 'installed status or resume dispatch failed');
        expect(statuses[3] === 1, 'incomplete synthetic run unexpectedly passed installed validate');
      } finally {
        console.log = priorLog;
        console.error = priorError;
      }
      for (const command of ['start', 'status', 'resume', 'validate']) {
        expect(
          captured.some((line) => line.includes(`\"command\":\"${command}\"`)),
          `installed launcher output omitted ${command} dispatch`,
        );
      }
    });

    await runAsyncCase(results, 'concurrent validate calls publish unique checks and kernel reports', async () => {
      const { runDir } = requireRun(context);
      const checkRoot = join(runDir, 'control', 'checks');
      const transactionRoot = join(runDir, 'control', 'transactions');
      const verificationRoot = join(runDir, 'verification');
      const checkNamesBefore = readdirSync(checkRoot)
        .filter((name) => /^CHECK-\d+\.json$/u.test(name))
        .sort();
      const transactionNamesBefore = readdirSync(transactionRoot)
        .filter((name) => /^TXN-checker-\d+\.json$/u.test(name))
        .sort();
      const reportNamesBefore = readdirSync(verificationRoot)
        .filter((name) => /^kernel-report(?:-\d+)?\.md$/u.test(name))
        .sort();
      const protectedCheck = readFileSync(join(checkRoot, 'CHECK-0001.json'));
      const protectedReport = readFileSync(join(verificationRoot, 'kernel-report.md'));
      const cliPath = join(REPO_ROOT, 'adapters', 'loa', 'src', 'cli.ts');
      const barrier = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT);
      const completed = await Promise.all([
        runConcurrentValidateWorker(cliPath, context.loaRoot, RUN_ID, barrier),
        runConcurrentValidateWorker(cliPath, context.loaRoot, RUN_ID, barrier),
      ]);
      expect(
        completed.every((entry) => entry.status === 1),
        `concurrent incomplete validates had unexpected exit status: ${stableJson(completed)}`,
      );
      const checkNamesAfter = readdirSync(checkRoot)
        .filter((name) => /^CHECK-\d+\.json$/u.test(name))
        .sort();
      const transactionNamesAfter = readdirSync(transactionRoot)
        .filter((name) => /^TXN-checker-\d+\.json$/u.test(name))
        .sort();
      const reportNamesAfter = readdirSync(verificationRoot)
        .filter((name) => /^kernel-report(?:-\d+)?\.md$/u.test(name))
        .sort();
      expect(
        checkNamesAfter.length === checkNamesBefore.length + 2,
        `concurrent validates did not reserve two unique check IDs: ${checkNamesAfter.join(', ')}; processes: ${stableJson(completed)}`,
      );
      expect(
        transactionNamesAfter.length === transactionNamesBefore.length + 2,
        'concurrent validates did not commit two unique checker transactions',
      );
      expect(
        reportNamesAfter.length === reportNamesBefore.length + 2,
        `concurrent validates did not publish two unique reports: ${reportNamesAfter.join(', ')}`,
      );
      expect(
        new Set(checkNamesAfter).size === checkNamesAfter.length
          && new Set(transactionNamesAfter).size === transactionNamesAfter.length
          && new Set(reportNamesAfter).size === reportNamesAfter.length,
        'concurrent checker publication reused a result pathname',
      );
      for (const name of transactionNamesAfter.slice(transactionNamesBefore.length)) {
        expect(
          (readJsonFile(join(transactionRoot, name)) as Record<string, JsonValue>).status
            === 'committed',
          `concurrent checker transaction did not commit: ${name}`,
        );
      }
      expect(
        readFileSync(join(checkRoot, 'CHECK-0001.json')).equals(protectedCheck)
          && readFileSync(join(verificationRoot, 'kernel-report.md')).equals(protectedReport),
        'concurrent checker publication overwrote an earlier result',
      );
    });

    runCase(results, 'generic Core-stage human gates cannot jump and simulated authority cannot accept', () => {
      const { runDir } = requireRun(context);
      expectThrows(
        () => openHumanAuthorityGate(runDir, {
          gateId: 'GATE-PREMATURE-S13',
          gateType: 'precis-acceptance',
          stage: 'S13',
          now: '2040-01-02T03:05:00.000Z',
          request: { artifact: 'premature-fixture-precis' },
        }),
        /cannot jump from Core stage S0 to S13/iu,
        'premature cross-stage authority gate',
      );
      updateRunState(runDir, '2040-01-02T03:05:30.000Z', (draft) => {
        draft.execution.core_state = 'DISTILLING';
        draft.execution.stage = 'S8';
        draft.execution.stage_status = 'running';
        draft.execution.gate = null;
        draft.execution.halt = null;
      });
      const beforeOpen = structuredClone(readRunState(runDir));
      openHumanAuthorityGate(runDir, {
        gateId: 'GATE-S8-REFERENT',
        gateType: 'external-referent-resolution',
        stage: 'S8',
        now: '2040-01-02T03:06:00.000Z',
        request: { question: 'Fixture-simulated referent decision.' },
      });
      const openTransactionPath = join(
        runDir,
        'control',
        'transactions',
        'TXN-authority-open-GATE-S8-REFERENT.json',
      );
      const committedOpen = readJsonFile(openTransactionPath) as Record<string, JsonValue>;
      const { committed_at: _openCommittedAt, ...preparedOpen } = committedOpen;
      rmSync(join(runDir, 'control', 'gates', 'GATE-S8-REFERENT-request.json'));
      writeRunState(runDir, beforeOpen);
      writeJsonAtomic(openTransactionPath, { ...preparedOpen, status: 'prepared' });
      const recoveredOpen = recoverPendingAuthorityTransactions(runDir, {
        now: () => '2040-01-02T03:06:30.000Z',
      });
      expect(recoveredOpen.committed.length === 1, 'prepared gate-open transaction was not recovered');
      expect(
        existsSync(join(runDir, 'control', 'gates', 'GATE-S8-REFERENT-request.json')),
        'gate-open recovery did not restore its request artifact',
      );
      const halted = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(halted.result === 'BLOCKED', 'resume crossed a generic human authority gate');
      const beforeDecision = structuredClone(readRunState(runDir));
      recordHumanAuthorityDecision(runDir, {
        gateId: 'GATE-S8-REFERENT',
        authorityIdentity: 'fixture-simulated-human-authority',
        decision: 'approve',
        recordedAt: '2040-01-02T03:07:00.000Z',
        simulation: { kind: 'fixture-simulated' },
        response: { resolution: 'fixture-simulated-only' },
      });
      const decisionTransactionPath = join(
        runDir,
        'control',
        'transactions',
        'TXN-authority-decision-GATE-S8-REFERENT.json',
      );
      const committedDecision = readJsonFile(decisionTransactionPath) as Record<string, JsonValue>;
      const { committed_at: _decisionCommittedAt, ...preparedDecision } = committedDecision;
      rmSync(join(runDir, 'control', 'gates', 'GATE-S8-REFERENT-response.json'));
      writeRunState(runDir, beforeDecision);
      writeJsonAtomic(decisionTransactionPath, { ...preparedDecision, status: 'prepared' });
      const recoveredDecision = recoverPendingAuthorityTransactions(runDir, {
        now: () => '2040-01-02T03:07:30.000Z',
      });
      expect(recoveredDecision.committed.length === 1, 'prepared authority decision was not recovered');
      expect(
        readRunState(runDir).execution.gate?.status === 'approved',
        'authority decision recovery did not restore the approved gate state',
      );

      updateRunState(runDir, '2040-01-02T03:07:40.000Z', (draft) => {
        draft.execution.stage = 'S13';
        draft.execution.stage_status = 'entered';
        draft.execution.gate = null;
      });
      expectThrows(
        () => openHumanAuthorityGate(runDir, {
          gateId: 'GATE-UNVERIFIED-S13',
          gateType: 'precis-acceptance',
          stage: 'S13',
          now: '2040-01-02T03:07:45.000Z',
          request: { artifact: 'unverified-fixture-precis' },
        }),
        /requires Core state VERIFIED/iu,
        'S13 gate before VERIFIED state',
      );
      updateRunState(runDir, '2040-01-02T03:07:50.000Z', (draft) => {
        draft.execution.core_state = 'VERIFIED';
      });
      openHumanAuthorityGate(runDir, {
        gateId: 'GATE-S13-ACCEPTANCE',
        gateType: 'precis-acceptance',
        stage: 'S13',
        now: '2040-01-02T03:08:00.000Z',
        request: { artifact: 'fixture-simulated-precis' },
      });
      expectThrows(
        () => recordHumanAuthorityDecision(runDir, {
          gateId: 'GATE-S13-ACCEPTANCE',
          authorityIdentity: 'fixture-simulated-human-authority',
          decision: 'approve',
          recordedAt: '2040-01-02T03:09:00.000Z',
          simulation: { kind: 'fixture-simulated' },
          response: { acceptance: 'fixture-simulated-only' },
          approvedState: 'ACCEPTED',
        }),
        /fixture-simulated authority cannot confer acceptance/iu,
        'fixture-simulated S13 acceptance',
      );
      const stillHalted = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(stillHalted.result === 'BLOCKED', 'rejected simulated acceptance cleared the gate');
      const closed = recordHumanAuthorityDecision(runDir, {
        gateId: 'GATE-S13-ACCEPTANCE',
        authorityIdentity: 'fixture-simulated-human-authority',
        decision: 'approve',
        recordedAt: '2040-01-02T03:10:00.000Z',
        simulation: { kind: 'fixture-simulated' },
        response: { structural_gate_test: 'closed-without-acceptance' },
      });
      expect(closed.execution.core_state !== 'ACCEPTED', 'structural gate test conferred acceptance');
      expect(closed.full_mode === 'fixture-simulated', 'generic simulated gate lost run taint');
    });

    runCase(results, 'worker bundles enforce exact allowlists and withheld selectors', () => {
      const { runDir, state } = requireRun(context);
      const corpus = verifyCorpusSnapshot(runDir);
      const [shown, withheld] = corpus.files;
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const exactWithheld = exactWithheldInventory(
        bundle,
        runDir,
        'extractor',
        'S2',
        [shown.frozen_path],
      );
      expectThrows(
        () => assembleWorkerBundle({
          bundle,
          runDir,
          callId: 'CALL-WRONG-RUN-ID',
          runId: 'RUN-WRONG-IDENTITY',
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path],
          withheld: exactWithheld,
          taskLine: 'Attempt to dispatch under a different run identity.',
          modelIdentity: state.identity.models.extractor,
        }),
        /does not match pinned run/iu,
        'worker request with a foreign run ID',
      );
      const wrongBundle: VerifiedLoaBundle = {
        ...bundle,
        lock: {
          ...bundle.lock,
          bundle: {
            ...bundle.lock.bundle,
            digest: `sha256:${'0'.repeat(64)}`,
          },
        },
      };
      expectThrows(
        () => assembleWorkerBundle({
          bundle: wrongBundle,
          runDir,
          callId: 'CALL-WRONG-BUNDLE-ID',
          runId: RUN_ID,
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path],
          withheld: exactWithheld,
          taskLine: 'Attempt to dispatch under a different Core bundle identity.',
          modelIdentity: state.identity.models.extractor,
        }),
        /does not match the run-pinned bundle identity/iu,
        'worker request with a foreign bundle identity',
      );
      expectThrows(
        () => assembleWorkerBundle({
          bundle,
          runDir,
          callId: 'CALL-WRONG-ROLE-MODEL',
          runId: RUN_ID,
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path],
          withheld: exactWithheld,
          taskLine: 'Attempt to dispatch with another role model mapping.',
          modelIdentity: state.identity.models['verifier-l1'],
        }),
        /run-pinned mapping for role extractor/iu,
        'worker request with another role model identity',
      );
      for (const [index, controlPath] of ['control', 'control/run-state.json'].entries()) {
        expectThrows(
          () => assembleWorkerBundle({
            bundle,
            runDir,
            callId: `CALL-CONTROL-ALLOWLIST-${String(index + 1)}`,
            runId: RUN_ID,
            stage: 'S2',
            role: 'extractor',
            kind: 'producer',
            allowlist: [controlPath],
            withheld: [],
            taskLine: 'Attempt to expose adapter control state to a worker.',
            modelIdentity: state.identity.models.extractor,
          }),
          /may not expose adapter control state/iu,
          `worker control allowlist ${controlPath}`,
        );
      }
      expectThrows(
        () => assembleWorkerBundle({
          bundle,
          runDir,
          callId: 'CALL-WITHHELD-OVERLAP',
          runId: RUN_ID,
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path],
          withheld: [
            ...exactWithheld,
            {
              selector: shown.frozen_path,
              core_ref: coreBlindPolicyReference(bundle, 'extractor', 'S2'),
            },
          ],
          taskLine: 'Extract the allowlisted fixture source.',
          modelIdentity: state.identity.models.extractor,
        }),
        /withheld/iu,
        'allowlist and withheld overlap',
      );
      expectThrows(
        () => assembleWorkerBundle({
          bundle,
          runDir,
          callId: 'CALL-CORE-POLICY-WIDENED',
          runId: RUN_ID,
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path, withheld.frozen_path],
          withheld: exactWithheldInventory(
            bundle,
            runDir,
            'extractor',
            'S2',
            [shown.frozen_path, withheld.frozen_path],
          ),
          taskLine: 'Attempt to widen the Core-bound fixture source selection.',
          modelIdentity: state.identity.models.extractor,
        }),
        /Core blind policy permits at most one corpus source/iu,
        'Core-bound source allowlist widening',
      );
      expectThrows(
        () => assembleWorkerBundle({
          bundle,
          runDir,
          callId: 'CALL-MISSING-WITHHELD-INVENTORY',
          runId: RUN_ID,
          stage: 'S2',
          role: 'extractor',
          kind: 'producer',
          allowlist: [shown.frozen_path],
          withheld: exactWithheld.slice(1),
          taskLine: 'Attempt to omit a canonical withheld fixture path.',
          modelIdentity: state.identity.models.extractor,
        }),
        /exactly inventory every canonical run file/iu,
        'incomplete withheld inventory',
      );
      const assembled = assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-ALLOWLIST-ONLY',
        runId: RUN_ID,
        stage: 'S2',
        role: 'extractor',
        kind: 'producer',
        allowlist: [shown.frozen_path],
        withheld: exactWithheld,
        taskLine: 'Extract the allowlisted fixture source.',
        modelIdentity: state.identity.models.extractor,
      });
      const request = verifyWorkerBundle(assembled.root);
      expect(request.allowlist.length === 1, 'worker request widened its file allowlist');
      expect(
        request.withheld.every((entry) => entry.core_ref.endsWith(`@${request.blind_policy.digest}`)),
        'worker request withheld inventory is not bound to the exact Core policy slice',
      );
      expect(request.allowlist[0].run_path === shown.frozen_path, 'worker request attached a different file');
      expect(
        readFileSync(join(assembled.root, request.allowlist[0].attachment_path))
          .equals(readFileSync(join(runDir, shown.frozen_path))),
        'worker attachment is not an exact copy',
      );
      const hiddenBytes = readFileSync(join(runDir, withheld.frozen_path));
      const materialized = walkRegularFiles(assembled.root)
        .filter((path) => !path.endsWith('request.json'))
        .map((path) => readFileSync(path));
      expect(
        !materialized.some((bytes) => bytes.includes(hiddenBytes)),
        'withheld source bytes leaked into the worker bundle',
      );
    });

    runCase(results, 'verifier lenses are restricted to their canonical Core stages', () => {
      const { runDir } = requireRun(context);
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const verifierStages: Array<{
        role: LoaRoleId;
        allowed: CoreStage[];
        rejected: CoreStage;
      }> = [
        { role: 'verifier-l1', allowed: ['S2'], rejected: 'S3' },
        { role: 'verifier-l2', allowed: ['S3'], rejected: 'S2' },
        { role: 'verifier-l3', allowed: ['S4'], rejected: 'S5' },
        { role: 'verifier-l4', allowed: ['S5'], rejected: 'S4' },
        { role: 'verifier-l5', allowed: ['S4', 'S5'], rejected: 'S6' },
        { role: 'verifier-l6', allowed: ['S6', 'S9a'], rejected: 'S7' },
        { role: 'verifier-l7', allowed: ['S8'], rejected: 'S9a' },
        { role: 'verifier-l8', allowed: ['S9b'], rejected: 'S8' },
        { role: 'verifier-l9', allowed: ['S10'], rejected: 'S11' },
        { role: 'verifier-l10', allowed: ['P1', 'P2', 'P3'], rejected: 'S13' },
      ];
      for (const spec of verifierStages) {
        for (const stage of spec.allowed) {
          expect(
            coreBlindPolicyReference(bundle, spec.role, stage).includes('@sha256:'),
            `${spec.role} did not resolve its canonical ${stage} lens policy`,
          );
        }
        expectThrows(
          () => coreBlindPolicyReference(bundle, spec.role, spec.rejected),
          /cannot run at/iu,
          `${spec.role} at noncanonical stage ${spec.rejected}`,
        );
      }
    });

    runCase(results, 'native worker handoffs reject every non-pinned host receipt', () => {
      const { runDir, state } = requireRun(context);
      const corpus = verifyCorpusSnapshot(runDir);
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const allowlist = [corpus.files[0].frozen_path];
      const assembled = assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-HOST-PIN-REJECTION',
        runId: RUN_ID,
        stage: 'S2',
        role: 'extractor',
        kind: 'producer',
        allowlist,
        withheld: exactWithheldInventory(
          bundle,
          runDir,
          'extractor',
          'S2',
          allowlist,
        ),
        taskLine: 'Prove native dispatch rejects substituted host receipts.',
        modelIdentity: state.identity.models.extractor,
      });
      const returnRoot = join(
        runDir,
        'control',
        'worker-returns',
        assembled.request.call_id,
      );
      const pinned = readRuntime(runDir).host;
      const changedVersion = structuredClone(pinned);
      changedVersion.host.version = 'loa-substitute-v1';
      const changedBuild = structuredClone(pinned);
      changedBuild.host.build_id = `sha256:${'1'.repeat(64)}`;
      const changedSimulation = structuredClone(pinned);
      changedSimulation.simulation = null;
      for (const [label, hostCapabilities] of [
        ['version', changedVersion],
        ['build', changedBuild],
        ['simulation', changedSimulation],
      ] as const) {
        expectThrows(
          () => prepareLoaWorkerHandoff({
            workerBundleRoot: assembled.root,
            returnRoot,
            hostCapabilities,
          }),
          /run-pinned host capability receipt/iu,
          `shape-valid ${label} host substitution`,
        );
      }
      let hostInvoked = false;
      expectThrows(
        () => dispatchLoaWorker({
          workerBundleRoot: assembled.root,
          returnRoot,
          hostCapabilities: changedBuild,
          host: {
            invokeFreshContext() {
              hostInvoked = true;
              throw new Error('substituted host was invoked');
            },
          },
        }),
        /run-pinned host capability receipt/iu,
        'direct worker dispatch with substituted host receipt',
      );
      expect(!hostInvoked, 'direct dispatch invoked the host before checking the run pin');
      const foreignReceiptPath = join(
        context.tempRoot,
        'shape-valid-foreign-host-capabilities.json',
      );
      writeJsonAtomic(foreignReceiptPath, pinned);
      expectThrows(
        () => prepareLoaWorkerHandoff({
          workerBundleRoot: assembled.root,
          returnRoot,
          hostCapabilities: pinned,
          hostCapabilitiesPath: foreignReceiptPath,
        }),
        /canonical run-pinned host receipt/iu,
        'shape-valid receipt at a foreign CLI path',
      );
      expect(!existsSync(returnRoot), 'rejected host substitutions materialized a worker handoff');
    });

    runCase(results, 'dispatch receipts bind model context and fresh refuters to distinct contexts', () => {
      const { runDir, state } = requireRun(context);
      const corpus = verifyCorpusSnapshot(runDir);
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const refuterAllowlist = [corpus.files[0].frozen_path];
      const assembleRefuter = (callId: string) => assembleWorkerBundle({
        bundle,
        runDir,
        callId,
        runId: RUN_ID,
        stage: 'S2',
        role: 'verifier-l1',
        kind: 'refuter',
        allowlist: refuterAllowlist,
        withheld: exactWithheldInventory(
          bundle,
          runDir,
          'verifier-l1',
          'S2',
          refuterAllowlist,
        ),
        taskLine: 'Attempt to refute fixture extraction coverage.',
        modelIdentity: state.identity.models['verifier-l1'],
        producerContextId: 'CTX-FIXTURE-PRODUCER',
      });
      for (const [index, producerContextId] of [undefined, '', '   '].entries()) {
        expectThrows(
          () => assembleWorkerBundle({
            bundle,
            runDir,
            callId: `CALL-REFUTER-WITHOUT-PRODUCER-${String(index + 1)}`,
            runId: RUN_ID,
            stage: 'S2',
            role: 'verifier-l1',
            kind: 'refuter',
            allowlist: refuterAllowlist,
            withheld: exactWithheldInventory(
              bundle,
              runDir,
              'verifier-l1',
              'S2',
              refuterAllowlist,
            ),
            taskLine: 'Attempt to refute without a bound producer context.',
            modelIdentity: state.identity.models['verifier-l1'],
            producerContextId,
          }),
          /requires a nonempty producer context ID/iu,
          `refuter with empty producer context identity ${String(index + 1)}`,
        );
      }
      const refuter = assembleRefuter('CALL-FRESH-REFUTER');
      const reused = fixtureDispatchReceipt(
        refuter.request,
        'CTX-FIXTURE-PRODUCER',
        'CTX-FIXTURE-PRODUCER',
      );
      expectThrows(
        () => validateWorkerDispatch(refuter.request, reused),
        /reused the producer context/iu,
        'refuter producer-context reuse',
      );
      const distinct = fixtureDispatchReceipt(
        refuter.request,
        'CTX-FIXTURE-REFUTER',
        'CTX-FIXTURE-PRODUCER',
      );
      validateWorkerDispatch(refuter.request, distinct);
      const raw = {
        verdict: 'upheld',
        rationale: 'Fixture-simulated attack found no omitted span in the allowlisted material.',
        attacks_tried: ['Compared the allowlisted source with the fixture packet boundary.'],
        evidence_ids: [corpus.files[0].source_id],
        missing_for_determination: null,
        flags: ['fixture-simulated'],
      };
      let hostInvocations = 0;
      const accepted = dispatchLoaWorker({
        workerBundleRoot: refuter.root,
        returnRoot: join(runDir, 'control', 'worker-returns', refuter.request.call_id),
        hostCapabilities: readRuntime(runDir).host,
        host: {
          invokeFreshContext(invocation) {
            hostInvocations += 1;
            expect(invocation.worker_bundle_root === refuter.root, 'host bridge received the wrong worker root');
            expect(
              invocation.readable_paths.length === 1
                && invocation.readable_paths[0] === refuter.root,
              'host bridge widened worker readable paths',
            );
            expect(invocation.writable_paths.length === 0, 'host bridge granted worker write paths');
            expect(invocation.inherit_context === false, 'host bridge inherited orchestrator context');
            expect(invocation.require_fresh_context === true, 'host bridge did not require fresh context');
            expect(invocation.require_exact_model_identity === true, 'host bridge did not require exact model identity');
            return { receipt: distinct, structured_return: raw };
          },
        },
      });
      expect(hostInvocations === 1, 'Loa worker bridge did not invoke exactly one fixture host');
      expect(accepted.report.result === 'PASS' && accepted.validated !== null, 'fresh refuter return failed validation');
      expect(
        accepted.report.simulation?.kind === 'fixture-simulated'
          && accepted.validated.simulation?.kind === 'fixture-simulated',
        'validated refuter return lost its fixture-simulated taint',
      );
      expect(existsSync(accepted.dispatchRecordPath), 'worker bridge did not persist dispatch evidence');
      expect(
        distinct.simulation?.kind === 'fixture-simulated',
        'synthetic refuter dispatch lost its simulation label',
      );

      const nativeRefuter = assembleRefuter('CALL-FRESH-REFUTER-NATIVE');
      const nativeReceipt = fixtureDispatchReceipt(
        nativeRefuter.request,
        'CTX-FIXTURE-REFUTER-NATIVE',
        'CTX-FIXTURE-PRODUCER',
      );
      const nativeReturnRoot = join(
        runDir,
        'control',
        'worker-returns',
        nativeRefuter.request.call_id,
      );
      const prepared = prepareLoaWorkerHandoff({
        workerBundleRoot: nativeRefuter.root,
        returnRoot: nativeReturnRoot,
        hostCapabilities: readRuntime(runDir).host,
      });
      expect(
        prepared.invocation.readable_paths.length === 1
          && prepared.invocation.readable_paths[0] === nativeRefuter.root
          && prepared.invocation.writable_paths.length === 0
          && prepared.invocation.inherit_context === false
          && prepared.invocation.require_fresh_context === true,
        'durable native handoff widened the sealed worker boundary',
      );
      const nativeDispatch = {
        format: 'aleph-loa-native-worker-dispatch/v1',
        invocation_digest: prepared.invocation.invocation_digest,
        worker_bundle_digest: prepared.invocation.worker_bundle_digest,
        host_capability_receipt_digest: prepared.invocation.host_capability_receipt.digest,
        receipt: nativeReceipt,
      };
      writeFileSync(prepared.nativeDispatchPath, stableJsonBytes(nativeDispatch), { mode: 0o400 });
      writeFileSync(prepared.nativeReturnPath, stableJsonBytes(raw), { mode: 0o400 });
      chmodSync(prepared.nativeDispatchPath, 0o400);
      chmodSync(prepared.nativeReturnPath, 0o400);
      const nativeAccepted = acceptLoaWorkerHandoff({
        workerBundleRoot: nativeRefuter.root,
        returnRoot: nativeReturnRoot,
      });
      expect(
        nativeAccepted.report.result === 'PASS'
          && nativeAccepted.validated !== null
          && nativeAccepted.report.simulation?.kind === 'fixture-simulated',
        'durable native handoff did not validate with preserved simulation taint',
      );
      expect(
        !existsSync(join(runDir, 'ledgers', 'native-handoff.md')),
        'native handoff crossed directly into a canonical ledger',
      );

      const tamperedRefuter = assembleRefuter('CALL-FRESH-REFUTER-NATIVE-TAMPER');
      const tamperedReceipt = fixtureDispatchReceipt(
        tamperedRefuter.request,
        'CTX-FIXTURE-REFUTER-NATIVE-TAMPER',
        'CTX-FIXTURE-PRODUCER',
      );
      const tamperedReturnRoot = join(
        runDir,
        'control',
        'worker-returns',
        tamperedRefuter.request.call_id,
      );
      const tampered = prepareLoaWorkerHandoff({
        workerBundleRoot: tamperedRefuter.root,
        returnRoot: tamperedReturnRoot,
        hostCapabilities: readRuntime(runDir).host,
      });
      writeFileSync(tampered.nativeDispatchPath, stableJsonBytes({
        format: 'aleph-loa-native-worker-dispatch/v1',
        invocation_digest: `sha256:${'0'.repeat(64)}`,
        worker_bundle_digest: tampered.invocation.worker_bundle_digest,
        host_capability_receipt_digest: tampered.invocation.host_capability_receipt.digest,
        receipt: tamperedReceipt,
      }), { mode: 0o400 });
      writeFileSync(tampered.nativeReturnPath, stableJsonBytes(raw), { mode: 0o400 });
      chmodSync(tampered.nativeDispatchPath, 0o400);
      chmodSync(tampered.nativeReturnPath, 0o400);
      expectThrows(
        () => acceptLoaWorkerHandoff({
          workerBundleRoot: tamperedRefuter.root,
          returnRoot: tamperedReturnRoot,
        }),
        /not exactly bound to the sealed invocation/iu,
        'tampered native dispatch binding',
      );
    });

    runCase(results, 'malformed or unbound worker returns cannot reach canonical ledgers', () => {
      const { runDir, state } = requireRun(context);
      const corpus = verifyCorpusSnapshot(runDir);
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const malformedAllowlist = [corpus.files[0].frozen_path];
      const assembled = assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-RETURN-MALFORMED',
        runId: RUN_ID,
        stage: 'S2',
        role: 'extractor',
        kind: 'producer',
        allowlist: malformedAllowlist,
        withheld: exactWithheldInventory(
          bundle,
          runDir,
          'extractor',
          'S2',
          malformedAllowlist,
        ),
        taskLine: 'Return a structured fixture extraction result.',
        modelIdentity: state.identity.models.extractor,
      });
      const receipt = fixtureDispatchReceipt(assembled.request, 'CTX-FIXTURE-PRODUCER-RETURN');
      const target = join(runDir, 'ledgers', 'synthetic-worker.md');
      const invalidReturnRoots = [
        {
          label: 'outside-run root',
          path: join(context.tempRoot, 'outside-worker-return'),
        },
        {
          label: 'wrong-call quarantine',
          path: join(runDir, 'control', 'worker-returns', 'CALL-WRONG-RETURN-ROOT'),
        },
        {
          label: 'canonical verification path',
          path: join(runDir, 'verification'),
        },
      ];
      for (const invalid of invalidReturnRoots) {
        expectThrows(
          () => prepareLoaWorkerHandoff({
            workerBundleRoot: assembled.root,
            returnRoot: invalid.path,
            hostCapabilities: readRuntime(runDir).host,
          }),
          /worker return root must exactly match/iu,
          `handoff prepare with ${invalid.label}`,
        );
        expectThrows(
          () => acceptLoaWorkerHandoff({
            workerBundleRoot: assembled.root,
            returnRoot: invalid.path,
          }),
          /worker return root must exactly match/iu,
          `handoff acceptance with ${invalid.label}`,
        );
        expectThrows(
          () => validateWorkerReturn({
            workerBundleRoot: assembled.root,
            returnRoot: invalid.path,
            raw: {
              source_id: corpus.files[0].source_id,
              packets: [],
              walk_complete: true,
              resume_point: null,
              notes: [],
            },
            dispatchReceipt: receipt,
          }),
          /worker return root must exactly match/iu,
          `direct validation with ${invalid.label}`,
        );
      }
      expect(
        !existsSync(join(context.tempRoot, 'outside-worker-return'))
          && !existsSync(join(
            runDir,
            'control',
            'worker-returns',
            'CALL-WRONG-RETURN-ROOT',
          ))
          && !existsSync(join(runDir, 'verification', 'raw.json')),
        'rejected worker return roots received quarantine artifacts',
      );
      expectThrows(
        () => validateWorkerReturn({
          workerBundleRoot: assembled.root,
          raw: { source_id: 'SRC-001', packets: [], walk_complete: true, resume_point: null, notes: [] },
          dispatchReceipt: undefined as unknown as WorkerDispatchReceipt,
        }),
        /dispatch|receipt|undefined|properties/iu,
        'worker return without dispatch receipt',
      );
      expectThrows(
        () => validateWorkerReturn({
          workerBundleRoot: assembled.root,
          raw: { source_id: 'SRC-001', packets: [], walk_complete: true, resume_point: null, notes: [] },
          dispatchReceipt: fixtureDispatchReceipt(
            assembled.request,
            'CTX-FIXTURE-PRODUCER-RETURN',
            'CTX-WRONG-PRODUCER',
          ),
        }),
        /producer context disagrees/iu,
        'worker return with mismatched producer context',
      );
      const malformed = validateWorkerReturn({
        workerBundleRoot: assembled.root,
        raw: readFileSync(join(FIXTURE_ROOT, 'worker-returns', 'malformed.json')),
        dispatchReceipt: receipt,
      });
      expect(malformed.report.result === 'FAIL', 'malformed worker return unexpectedly passed');
      expect(malformed.validated === null, 'malformed worker return received validation brand');
      const writer = new LedgerWriter(runDir, CLOCK);
      expectThrows(
        () => writer.append(
          'ledgers/synthetic-worker.md',
          malformed.validated as unknown as ValidatedWorkerReturn<JsonValue>,
          (value) => stableJson(value),
        ),
        /validated worker return/iu,
        'ledger append from malformed return',
      );
      expect(!existsSync(target), 'malformed return changed a canonical ledger');

      expectThrows(
        () => new ValidatedWorkerReturn(
          Symbol('forged'),
          assembled.request.call_id,
          {} as JsonValue,
          'sha256:forged',
          'sha256:forged',
          'sha256:forged',
          null,
        ),
        /only by validation/iu,
        'manual validation-brand forgery',
      );
      const validBundle = assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-RETURN-VALID',
        runId: RUN_ID,
        stage: 'S2',
        role: 'extractor',
        kind: 'producer',
        allowlist: malformedAllowlist,
        withheld: exactWithheldInventory(
          bundle,
          runDir,
          'extractor',
          'S2',
          malformedAllowlist,
        ),
        taskLine: 'Return a second structured fixture extraction result.',
        modelIdentity: state.identity.models.extractor,
      });
      const validReceipt = fixtureDispatchReceipt(
        validBundle.request,
        'CTX-FIXTURE-PRODUCER-VALID',
      );
      const validRaw = {
        source_id: corpus.files[0].source_id,
        packets: [],
        walk_complete: true,
        resume_point: null,
        notes: ['fixture-simulated structural return'],
      };
      const valid = validateWorkerReturn({
        workerBundleRoot: validBundle.root,
        raw: validRaw,
        dispatchReceipt: validReceipt,
      });
      expect(valid.report.result === 'PASS' && valid.validated !== null, 'valid structured return did not receive validation brand');
      validRaw.notes.push('mutation after validation must not enter the brand');
      expect(
        !stableJson(valid.validated.data).includes('mutation after validation'),
        'validated return retained a mutable caller object',
      );
      expectThrows(
        () => (valid.validated?.data as { notes: string[] }).notes.push('mutate frozen brand'),
        /read only|frozen|extensible|object/iu,
        'post-validation branded-data mutation',
      );
      expect(
        valid.report.simulation?.kind === 'fixture-simulated'
          && valid.validated.simulation?.kind === 'fixture-simulated',
        'validated producer return lost its fixture-simulated taint',
      );
      const retainedFailure = readJsonFile(join(
        runDir,
        'control',
        'worker-returns',
        assembled.request.call_id,
        'validation.json',
      )) as { result: string; simulation?: { kind?: string } | null };
      expect(retainedFailure.result === 'FAIL', 'malformed-return quarantine evidence was overwritten');
      expect(
        retainedFailure.simulation?.kind === 'fixture-simulated',
        'malformed-return quarantine lost its simulation label',
      );
      expect(!existsSync(target), 'worker validation itself wrote a canonical ledger');
      const relativeLedgerPath = 'ledgers/synthetic-worker.md';
      const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
      const stateBefore = structuredClone(readRunState(runDir));
      const targetBefore = existsSync(target) ? readFileSync(target) : null;
      const chainBefore = existsSync(chainPath) ? readFileSync(chainPath) : null;
      const ledgerReceipt = writer.append(
        relativeLedgerPath,
        valid.validated,
        (value) => `fixture-simulated validated return: ${stableJson(value)}`,
      );
      expect(ledgerReceipt.writer === 'loa-orchestrator', 'canonical receipt names a worker as writer');
      expect(existsSync(target), 'orchestrator writer did not update the canonical ledger');
      const after = readRunState(runDir);
      expect(after.ledger.writer_id === 'loa-orchestrator', 'run lost its sole ledger writer identity');
      expect(after.ledger.sequence === '1', 'ledger sequence did not advance exactly once');
      const transactionPath = join(
        runDir,
        'control',
        'transactions',
        `TXN-ledger-${ledgerReceipt.sequence}.json`,
      );
      const committedJournal = readJsonFile(transactionPath) as Record<string, unknown>;
      expect(committedJournal.status === 'committed', 'ledger transaction did not commit');
      context.ledgerRecovery = {
        runDir,
        relativePath: relativeLedgerPath,
        validated: valid.validated as ValidatedWorkerReturn<JsonValue>,
        stateBefore,
        targetBefore,
        chainBefore,
        receipt: ledgerReceipt,
        targetAfter: readFileSync(target),
        chainAfter: readFileSync(chainPath),
        transactionPath,
        committedJournal,
      };
    });

    runCase(results, 'committed ledger retries return the original receipt without appending', () => {
      const fixture = context.ledgerRecovery;
      expect(fixture !== null, 'committed ledger fixture is unavailable');
      const target = join(fixture.runDir, fixture.relativePath);
      const chainPath = join(fixture.runDir, 'control', 'ledger-chain.jsonl');
      const stateBeforeRetry = stableJson(readRunState(fixture.runDir));
      const targetBeforeRetry = readFileSync(target);
      const chainBeforeRetry = readFileSync(chainPath);
      const journalBeforeRetry = readFileSync(fixture.transactionPath);
      const recovery = recoverPendingLedgerTransactions(fixture.runDir, CLOCK);
      expect(
        recovery.alreadyCommitted.some((receipt) => (
          receipt.sequence === fixture.receipt.sequence
          && receipt.return_digest === fixture.receipt.return_digest
        )),
        'committed journal was not recognized as already committed',
      );
      let renderCalls = 0;
      const retried = new LedgerWriter(fixture.runDir, CLOCK).append(
        fixture.relativePath,
        fixture.validated,
        (value) => {
          renderCalls += 1;
          return `unexpected duplicate: ${stableJson(value)}`;
        },
      );
      expect(renderCalls === 0, 'committed retry invoked the ledger renderer');
      expect(
        stableJson(retried) === stableJson(fixture.receipt),
        'committed retry did not return the original receipt',
      );
      expect(readFileSync(target).equals(targetBeforeRetry), 'committed retry changed the ledger');
      expect(readFileSync(chainPath).equals(chainBeforeRetry), 'committed retry changed the chain');
      expect(
        readFileSync(fixture.transactionPath).equals(journalBeforeRetry),
        'committed retry rewrote its transaction journal',
      );
      expect(
        stableJson(readRunState(fixture.runDir)) === stateBeforeRetry,
        'committed retry changed run state',
      );
    });

    runCase(results, 'forged committed journals cannot outrun canonical ledger state', () => {
      const fixture = context.ledgerRecovery;
      expect(fixture !== null, 'committed ledger fixture is unavailable');
      const state = readRunState(fixture.runDir);
      const target = join(fixture.runDir, fixture.relativePath);
      const targetBytes = readFileSync(target);
      const chainPath = join(fixture.runDir, 'control', 'ledger-chain.jsonl');
      const chainBefore = readFileSync(chainPath);
      const sequence = String(Number(fixture.receipt.sequence) + 1);
      const base = {
        format: 'aleph-loa-ledger-receipt/v1' as const,
        sequence,
        path: fixture.relativePath,
        before_digest: sha256Digest(targetBytes),
        after_digest: sha256Digest(targetBytes),
        return_digest: sha256Digest('forged-uncommitted-return'),
        previous_chain_digest: state.ledger.chain_head,
        writer: 'loa-orchestrator' as const,
        written_at: '2040-01-02T03:09:00.000Z',
      };
      const forged: LedgerReceipt = {
        ...base,
        chain_digest: sha256Digest(stableJsonBytes(base)),
      };
      const chainAfter = Buffer.from(`${chainBefore.toString('utf8')}${stableJson(forged)}\n`, 'utf8');
      const transactionPath = join(
        fixture.runDir,
        'control',
        'transactions',
        `TXN-ledger-${sequence}.json`,
      );
      writeFileSync(chainPath, chainAfter);
      writeFileSync(transactionPath, stableJson({
        format: 'aleph-loa-ledger-transaction/v1',
        status: 'committed',
        sequence,
        path: fixture.relativePath,
        before_digest: forged.before_digest,
        after_digest: forged.after_digest,
        chain_before_digest: sha256Digest(chainBefore),
        chain_after_digest: sha256Digest(chainAfter),
        prior_state_checkpoint: state.execution.resume.checkpoint_digest,
        receipt: forged,
        prepared_at: forged.written_at,
        committed_at: forged.written_at,
      }));
      try {
        expectThrows(
          () => recoverPendingLedgerTransactions(fixture.runDir, CLOCK),
          /chain head or sequence disagrees/iu,
          'forged committed ledger journal',
        );
      } finally {
        writeFileSync(chainPath, chainBefore);
        rmSync(transactionPath, { force: true });
      }
    });

    runCase(results, 'prepared ledger journals roll back or forward without duplicate append', () => {
      const fixture = context.ledgerRecovery;
      expect(fixture !== null, 'committed ledger fixture is unavailable');
      const target = join(fixture.runDir, fixture.relativePath);
      const chainPath = join(fixture.runDir, 'control', 'ledger-chain.jsonl');
      const prepareJournal = (): void => {
        const journal = structuredClone(fixture.committedJournal);
        journal.status = 'prepared';
        delete journal.committed_at;
        delete journal.recovered_at;
        writeFileSync(fixture.transactionPath, stableJson(journal));
      };
      const restoreImage = (path: string, bytes: Buffer | null): void => {
        if (bytes === null) rmSync(path, { force: true });
        else writeFileSync(path, bytes);
      };

      writeRunState(fixture.runDir, structuredClone(fixture.stateBefore));
      restoreImage(target, fixture.targetBefore);
      restoreImage(chainPath, fixture.chainBefore);
      prepareJournal();
      const staleLock = join(fixture.runDir, 'control', 'ledger-writer.lock');
      writeFileSync(staleLock, stableJson({
        format: 'aleph-loa-ledger-lock/v1',
        pid: '999999999',
        acquired_at: '2039-01-01T00:00:00.000Z',
        nonce: `sha256:${'0'.repeat(64)}`,
      }));
      const rolledBack = recoverPendingLedgerTransactions(fixture.runDir, CLOCK);
      expect(!existsSync(staleLock), 'resume-time recovery retained a dead writer lock');
      expect(
        rolledBack.rolledBack.includes(`TXN-ledger-${fixture.receipt.sequence}.json`),
        'all-before prepared transaction did not roll back',
      );
      expect(
        stableJson(readRunState(fixture.runDir)) === stableJson(fixture.stateBefore),
        'rollback changed the before-state checkpoint',
      );
      expect(
        fixture.targetBefore === null ? !existsSync(target) : readFileSync(target).equals(fixture.targetBefore),
        'rollback changed the target before-image',
      );
      expect(
        fixture.chainBefore === null ? !existsSync(chainPath) : readFileSync(chainPath).equals(fixture.chainBefore),
        'rollback changed the chain before-image',
      );
      expect(
        (readJsonFile(fixture.transactionPath) as { status?: string }).status === 'rolled-back',
        'rollback did not durably close the prepared journal',
      );

      writeRunState(fixture.runDir, structuredClone(fixture.stateBefore));
      restoreImage(target, fixture.targetAfter);
      restoreImage(chainPath, fixture.chainBefore);
      prepareJournal();
      const recoveredReceipt = new LedgerWriter(fixture.runDir, CLOCK).append(
        fixture.relativePath,
        fixture.validated,
        (value) => `fixture-simulated validated return: ${stableJson(value)}`,
      );
      expect(
        stableJson(recoveredReceipt) === stableJson(fixture.receipt),
        'roll-forward did not return the prepared receipt',
      );
      expect(readFileSync(target).equals(fixture.targetAfter), 'roll-forward duplicated the target append');
      expect(readFileSync(chainPath).equals(fixture.chainAfter), 'roll-forward duplicated the chain append');
      const recoveredState = readRunState(fixture.runDir);
      expect(recoveredState.ledger.sequence === fixture.receipt.sequence, 'roll-forward advanced ledger sequence twice');
      expect(recoveredState.ledger.chain_head === fixture.receipt.chain_digest, 'roll-forward recorded the wrong chain head');
      expect(
        (readJsonFile(fixture.transactionPath) as { status?: string }).status === 'committed',
        'roll-forward did not durably commit the prepared journal',
      );
    });

    runCase(results, 'launcher rejects a self-resealed receipt that omits locked runtime coverage', () => {
      const receiptPath = join(context.loaRoot, LOA_INSTALL_LOCK_PATH);
      const original = readFileSync(receiptPath);
      const lock = JSON.parse(original.toString('utf8')) as LoaInstallLock;
      const omitted = lock.files.find((file) => (
        file.kind === 'runtime'
        && file.source_path === 'README.md'
      ));
      expect(omitted !== undefined, 'launcher omission fixture lacks README.md runtime record');
      const resealed = resealLoaInstallLock({
        ...lock,
        files: lock.files.filter((file) => file !== omitted),
      });
      writeFileSync(receiptPath, stableJsonBytes(resealed));
      expectThrows(
        () => verifyInstalledLauncherRuntime(context.loaRoot),
        /exact bundle|cover|inventory|receipt/iu,
        'launcher self-resealed receipt omission',
      );
      writeFileSync(receiptPath, original);
      const restored = verifyLoaInstallation(context.loaRoot);
      expect(
        restored.result === 'PASS',
        `receipt-omission fixture did not restore: ${restored.errors.join('; ')}`,
      );
    });

    runCase(results, 'launcher rejects a tampered runtime before importing executable adapter code', () => {
      const cli = join(
        installedBundleRoot(context.loaRoot),
        'adapters',
        'loa',
        'src',
        'cli.ts',
      );
      const sentinel = join(context.tempRoot, 'tampered-cli-executed.txt');
      const original = readFileSync(cli);
      const originalMode = lstatSync(cli).mode & 0o777;
      chmodSync(cli, 0o600);
      writeFileSync(cli, Buffer.concat([
        original,
        Buffer.from(
          `\nawait import('node:fs').then((module) => module.writeFileSync(${JSON.stringify(sentinel)}, 'executed\\n'));\n`,
          'utf8',
        ),
      ]));
      expectThrows(
        () => verifyInstalledLauncherRuntime(context.loaRoot),
        /tampered|digest|verification/iu,
        'launcher pre-import runtime verification',
      );
      expect(!existsSync(sentinel), 'tampered CLI executed before launcher verification');
      writeFileSync(cli, original);
      chmodSync(cli, originalMode);
      const restored = verifyLoaInstallation(context.loaRoot);
      expect(restored.result === 'PASS', `fixture installation did not restore: ${restored.errors.join('; ')}`);
    });

    runCase(results, 'tampered worker bundle and run-local runtime fail closed', () => {
      const { runDir, state } = requireRun(context);
      const corpus = verifyCorpusSnapshot(runDir);
      const bundle = verifyAndLoadLoaBundle(readRuntime(runDir).bundle.root);
      const worker = assembleWorkerBundle({
        bundle,
        runDir,
        callId: 'CALL-TAMPERED-BUNDLE',
        runId: RUN_ID,
        stage: 'S2',
        role: 'extractor',
        kind: 'producer',
        allowlist: [corpus.files[0].frozen_path],
        withheld: exactWithheldInventory(
          bundle,
          runDir,
          'extractor',
          'S2',
          [corpus.files[0].frozen_path],
        ),
        taskLine: 'Exercise worker bundle tamper detection.',
        modelIdentity: state.identity.models.extractor,
      });
      const attachment = join(worker.root, worker.request.allowlist[0].attachment_path);
      chmodSync(attachment, 0o600);
      writeFileSync(attachment, Buffer.concat([readFileSync(attachment), Buffer.from('tamper', 'utf8')]));
      expectThrows(
        () => verifyWorkerBundle(worker.root),
        /digest mismatch|attachment changed/iu,
        'tampered worker bundle verification',
      );

      const runtime = verifyRuntimeSnapshot(runtimeSnapshotPath(runDir), { allowSimulation: true });
      const activeRuntime = installedBundleRoot(context.loaRoot);
      makeTreeWritable(activeRuntime);
      rmSync(activeRuntime, { recursive: true, force: true });
      expect(verifyLoaInstallation(context.loaRoot).result === 'FAIL', 'missing active installation still verifies');
      const pinnedResume = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(pinnedResume.result === 'PASS', `run did not survive active runtime removal: ${pinnedResume.errors.join('; ')}`);
      expect(runtime.bundle.root.startsWith(`${runDir}${sep}`), 'runtime snapshot points outside the run directory');
      expect(existsSync(runtime.bundle.root), 'run-local original bundle was not retained');

      const runtimeFile = join(runtime.bundle.root, 'adapters', 'loa', 'command', 'loa-aleph.md');
      chmodSync(runtimeFile, 0o600);
      writeFileSync(runtimeFile, Buffer.concat([readFileSync(runtimeFile), Buffer.from('\ntampered\n', 'utf8')]));
      const tamperedResume = dispatchLoaCommand(['resume', RUN_ID], startOptions(context));
      expect(tamperedResume.result === 'FAIL', 'tampered run-local runtime resumed');
      expect(
        tamperedResume.errors.some((error) => /changed|digest|verify/iu.test(error)),
        `tampered runtime failure lacks diagnostic: ${tamperedResume.errors.join('; ')}`,
      );
    });

    runCase(results, 'fixture evidence stays simulated and never claims acceptance or live full mode', () => {
      const { runDir } = requireRun(context);
      const state = readRunState(runDir);
      assertFixtureBoundary(state, runDir);
      const gateResponse = readJsonFile(join(runDir, 'control', 'gates', 'GATE-S0-response.json')) as S0AuthorityResponse;
      expect(gateResponse.simulation?.kind === 'fixture-simulated', 'authority fixture is not explicitly simulated');
      const workerReceipts = walkRegularFiles(join(runDir, 'control', 'worker-returns'));
      expect(workerReceipts.length > 0, 'fixture produced no inspectable worker return evidence');
      expect(
        state.full_mode !== ('full-aleph' as LoaRunState['full_mode']),
        'synthetic machinery was mislabeled live full Aleph',
      );
    });
  } finally {
    makeTreeWritable(tempRoot);
    rmSync(tempRoot, { recursive: true, force: true });
  }
  return {
    result: results.every((entry) => entry.status === 'PASS') ? 'PASS' : 'FAIL',
    fixture: 'fixture-simulated',
    real_model_calls: 'none',
    cases: results,
  };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const help = args.includes('--help') || args.includes('-h');
  const unknown = args.filter((arg) => !['--json', '--help', '-h'].includes(arg));
  if (help) {
    console.log('Usage: node adapters/loa/tests/test-loa-adapter.ts [--json]');
    return;
  }
  if (unknown.length > 0) {
    console.error(`unknown argument ${unknown[0]}`);
    process.exitCode = 2;
    return;
  }
  const report = await runLoaAdapterTests();
  if (json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    for (const entry of report.cases) {
      console.log(
        `${entry.status} LOA-ADAPTER ${entry.name}`
        + (entry.error ? `: ${entry.error}` : ''),
      );
    }
    console.log(`EVIDENCE: ${report.fixture}; REAL MODEL CALLS: ${report.real_model_calls}`);
    console.log(`RESULT: ${report.result}`);
  }
  process.exitCode = report.result === 'PASS' ? 0 : 1;
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
