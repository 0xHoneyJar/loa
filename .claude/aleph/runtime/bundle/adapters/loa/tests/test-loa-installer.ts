#!/usr/bin/env node

import {
  spawnSync,
} from 'node:child_process';
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  assembleBundles,
  verifyBundle,
} from '../../../scripts/assemble-bundles.ts';
import {
  canonicalJson,
  canonicalJsonBytes,
  digestEntries,
  resealBundleLock,
  sha256Digest,
} from '../../../scripts/lib/bundle-format.ts';
import type { BundleLock } from '../../../scripts/lib/bundle-format.ts';
import {
  installLoaBundle,
  removeStaleManagedFiles,
  resealLoaInstallLock,
  verifyLoaInstallation,
} from '../src/installer.ts';
import type {
  LoaInstallationCheckpoint,
  LoaInstallationReport,
  LoaInstallLock,
  LoaManagedInstallFile,
} from '../src/installer.ts';
import { verifyInstalledLauncherRuntime } from '../src/launcher.ts';
import { acquireDurableProcessLock } from '../src/run-control.ts';
import {
  LOA_BUNDLE_ID,
  LOA_INSTALLED_BUNDLE_ROOT,
  LOA_INSTALL_LOCK_PATH,
} from '../src/types.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '../../..');
const INSTALLER_SOURCE_PATH = join(REPO_ROOT, 'adapters/loa/src/installer.ts');
const COMMAND_SOURCE = 'adapters/loa/command/loa-aleph.md';
const SKILL_SOURCE = 'adapters/loa/skill/loa-aleph/SKILL.md';
const LAUNCHER_SOURCE = 'runtime-js/adapters/loa/src/launcher.js';
const COMMAND_DESTINATION = '.claude/commands/loa-aleph.md';
const SKILL_DESTINATION = '.claude/skills/loa-aleph/SKILL.md';
const LAUNCHER_DESTINATION = '.claude/aleph/bin/loa-aleph.mjs';
const TRANSACTION_PATH = '.claude/aleph-install.transaction';
const INSTALL_WRITER_LOCK_PATH = '.claude/aleph-install.writer.lock';
const INSTALL_WRITER_LOCK_FORMAT = 'aleph-loa-install-writer-lock/v1';
const INSTALL_WRITER_LABEL = 'Loa installation writer';
const RUN_CONTROL_SOURCE_PATH = join(REPO_ROOT, 'adapters/loa/src/run-control.ts');
const INTERRUPTION_POINTS: LoaInstallationCheckpoint[] = [
  'after-transaction-prepared',
  'after-runtime-published',
  'after-command-published',
];

interface InstallerCaseResult {
  name: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

export interface InstallerTestReport {
  result: 'PASS' | 'FAIL';
  cases: InstallerCaseResult[];
}

interface InstallerTestContext {
  tempRoot: string;
  selectedBundle: string;
  nonselectedBundle: string;
  primaryTarget: string;
  primaryReceipt: Buffer | null;
  primarySummary: LoaInstallationReport['summary'];
}

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function expectThrows(
  operation: () => unknown,
  pattern: RegExp,
  label: string,
): void {
  let error = '';
  try {
    operation();
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
  }
  expect(pattern.test(error), `${label} did not fail as expected: ${error || 'no error'}`);
}

function expectRegularFile(path: string, label: string): void {
  expect(existsSync(path), `${label} is missing`);
  const stat = lstatSync(path);
  expect(stat.isFile() && !stat.isSymbolicLink(), `${label} is not a regular file`);
}

function expectInstallationPass(
  report: LoaInstallationReport,
  label: string,
): asserts report is LoaInstallationReport & {
  summary: NonNullable<LoaInstallationReport['summary']>;
} {
  expect(
    report.result === 'PASS' && report.summary !== undefined,
    `${label} failed: ${report.errors.join('; ') || 'missing summary'}`,
  );
}

function expectInstallationFail(report: LoaInstallationReport, label: string): void {
  expect(report.result === 'FAIL', `${label} unexpectedly passed`);
  expect(report.errors.length > 0, `${label} failed without a diagnostic`);
}

function installRecordPath(target: string): string {
  return join(target, LOA_INSTALL_LOCK_PATH);
}

function testWriterLockPath(target: string): string {
  return join(target, INSTALL_WRITER_LOCK_PATH);
}

function acquireLiveTestWriter(target: string): () => void {
  mkdirSync(join(target, '.claude'), { recursive: true });
  return acquireDurableProcessLock(testWriterLockPath(target), {
    format: INSTALL_WRITER_LOCK_FORMAT,
    label: INSTALL_WRITER_LABEL,
    acquiredAt: '2040-01-02T03:04:05.000Z',
  });
}

function leaveDeadTestWriter(target: string): void {
  mkdirSync(join(target, '.claude'), { recursive: true });
  const script = `
    import { acquireDurableProcessLock } from ${
      JSON.stringify(pathToFileURL(RUN_CONTROL_SOURCE_PATH).href)
    };
    acquireDurableProcessLock(
      ${JSON.stringify(testWriterLockPath(target))},
      {
        format: ${JSON.stringify(INSTALL_WRITER_LOCK_FORMAT)},
        label: ${JSON.stringify(INSTALL_WRITER_LABEL)},
        acquiredAt: '2040-01-02T03:04:06.000Z',
      },
    );
  `;
  const child = spawnSync(
    process.execPath,
    ['--input-type=module', '--eval', script],
    {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      maxBuffer: 8 * 1024 * 1024,
    },
  );
  expect(
    child.status === 0,
    `dead-writer setup failed: ${child.stderr || child.stdout}`,
  );
  expect(existsSync(testWriterLockPath(target)), 'dead writer left no durable lock');
}

function installedRuntime(target: string): string {
  return join(target, LOA_INSTALLED_BUNDLE_ROOT);
}

function canonicalSummary(summary: NonNullable<LoaInstallationReport['summary']>): string {
  return canonicalJson({
    ...summary,
    managedFileCount: String(summary.managedFileCount),
  });
}

function readInstallLock(target: string): LoaInstallLock {
  return JSON.parse(readFileSync(installRecordPath(target), 'utf8')) as LoaInstallLock;
}

function runCase(
  results: InstallerCaseResult[],
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

function assertExactExposure(
  context: InstallerTestContext,
  source: string,
  destination: string,
): void {
  const installed = join(context.primaryTarget, destination);
  expectRegularFile(installed, `installed exposure ${destination}`);
  const sourceBytes = readFileSync(join(context.selectedBundle, source));
  const installedBytes = readFileSync(installed);
  expect(installedBytes.equals(sourceBytes), `installed exposure differs from ${source}`);
}

function assertNoInstallRecord(target: string): void {
  expect(
    !existsSync(installRecordPath(target)),
    'rejected installation unexpectedly wrote an installation record',
  );
}

function cloneBundle(source: string, destination: string): void {
  cpSync(source, destination, {
    recursive: true,
    force: false,
    errorOnExist: true,
  });
}

function alternateVerifiedBundle(context: InstallerTestContext): string {
  const destination = join(context.tempRoot, 'bundle-alternate-update');
  cloneBundle(context.selectedBundle, destination);
  const commandPath = join(destination, COMMAND_SOURCE);
  writeFileSync(commandPath, Buffer.concat([
    readFileSync(commandPath),
    Buffer.from('\n<!-- alternate verified update image -->\n', 'utf8'),
  ]));
  const lockPath = join(destination, 'bundle.lock.json');
  const lock = JSON.parse(readFileSync(lockPath, 'utf8')) as BundleLock;
  const commandRecord = lock.files.find((file) => file.path === COMMAND_SOURCE);
  expect(commandRecord !== undefined, 'alternate bundle command is absent from its lock');
  commandRecord.digest = sha256Digest(readFileSync(commandPath));
  lock.adapter.tree_digest = digestEntries(
    lock.files.filter((file) => file.classification === 'adapter'),
  );
  lock.bundle.payload_digest = digestEntries(lock.files);
  writeFileSync(lockPath, canonicalJsonBytes(resealBundleLock(lock)));
  const verification = verifyBundle(destination);
  expect(
    verification.result === 'PASS',
    `alternate update bundle failed verification: ${verification.errors.join('; ')}`,
  );
  return destination;
}

function addPreservedState(target: string, label: string): {
  unmanagedCommand: string;
  unmanagedSkill: string;
  runFile: string;
} {
  const unmanagedCommand = join(target, '.claude/commands/operator-owned.md');
  const unmanagedSkill = join(target, '.claude/skills/operator-owned/SKILL.md');
  const runFile = join(
    target,
    'grimoires/loa/aleph/runs',
    `RUN-${label}`,
    'control/run-state.json',
  );
  for (const path of [unmanagedCommand, unmanagedSkill, runFile]) {
    mkdirSync(dirname(path), { recursive: true });
  }
  writeFileSync(unmanagedCommand, `operator command ${label}\n`);
  writeFileSync(unmanagedSkill, `operator skill ${label}\n`);
  writeFileSync(runFile, `retained run ${label}\n`);
  return { unmanagedCommand, unmanagedSkill, runFile };
}

function assertPreservedState(
  paths: ReturnType<typeof addPreservedState>,
  label: string,
): void {
  expect(
    readFileSync(paths.unmanagedCommand, 'utf8') === `operator command ${label}\n`,
    `unmanaged command was changed for ${label}`,
  );
  expect(
    readFileSync(paths.unmanagedSkill, 'utf8') === `operator skill ${label}\n`,
    `unmanaged skill was changed for ${label}`,
  );
  expect(
    readFileSync(paths.runFile, 'utf8') === `retained run ${label}\n`,
    `retained run was changed for ${label}`,
  );
}

function addStaleManagedExposure(target: string): {
  staleDestination: string;
  previous: LoaInstallLock;
  next: LoaInstallLock;
} {
  const lock = readInstallLock(target);
  const command = lock.files.find((file) => (
    file.kind === 'exposure' && file.destination_path === COMMAND_DESTINATION
  ));
  expect(command !== undefined, 'installed command exposure is absent from the receipt');
  const staleDestination = '.claude/commands/loa-aleph-stale-managed.md';
  const staleFile: LoaManagedInstallFile = {
    ...command,
    destination_path: staleDestination,
  };
  const staleAbsolute = join(target, staleDestination);
  mkdirSync(dirname(staleAbsolute), { recursive: true });
  writeFileSync(staleAbsolute, readFileSync(join(target, command.destination_path)));
  const previous = resealLoaInstallLock({
    ...lock,
    files: [...lock.files, staleFile],
  });
  return { staleDestination, previous, next: lock };
}

function assertInstallerHasNoNetworkImports(): void {
  const source = readFileSync(INSTALLER_SOURCE_PATH, 'utf8');
  const imports: string[] = [];
  const pattern = /\bfrom\s+['"]([^'"]+)['"]|\bimport\s*\(\s*['"]([^'"]+)['"]/gu;
  for (const match of source.matchAll(pattern)) {
    const specifier = match[1] || match[2];
    if (specifier) imports.push(specifier);
  }
  expect(imports.length > 0, 'installer source exposed no inspectable imports');
  const forbiddenBuiltins = new Set([
    'node:dns',
    'node:http',
    'node:http2',
    'node:https',
    'node:net',
    'node:tls',
  ]);
  for (const specifier of imports) {
    expect(
      specifier.startsWith('.') || specifier.startsWith('node:'),
      `installer imports a nonlocal package: ${specifier}`,
    );
    expect(!forbiddenBuiltins.has(specifier), `installer imports network module ${specifier}`);
  }
  const forbiddenOperations = [
    /\bfetch\s*\(/u,
    /\b(?:curl|wget)\b/iu,
    /\bgit\s+(?:clone|fetch|pull)\b/iu,
    /\bnpm\s+(?:ci|install)\b/iu,
  ];
  for (const operation of forbiddenOperations) {
    expect(!operation.test(source), `installer contains network operation ${String(operation)}`);
  }
}

function prepareContext(tempRoot: string): InstallerTestContext {
  const output = join(tempRoot, 'assembled');
  const assembly = assembleBundles(REPO_ROOT, output);
  expect(
    assembly.result === 'PASS',
    `bundle assembly failed: ${assembly.errors.join('; ')}`,
  );
  const selected = assembly.bundles.find((bundle) => bundle.id === LOA_BUNDLE_ID);
  const nonselected = assembly.bundles.find((bundle) => bundle.id !== LOA_BUNDLE_ID);
  expect(selected !== undefined, `assembly did not emit ${LOA_BUNDLE_ID}`);
  expect(nonselected !== undefined, 'assembly did not emit a nonselected host bundle');
  const selectedVerification = verifyBundle(selected.path);
  expect(
    selectedVerification.result === 'PASS'
      && selectedVerification.summary?.id === LOA_BUNDLE_ID,
    `selected bundle failed verification: ${selectedVerification.errors.join('; ')}`,
  );
  return {
    tempRoot,
    selectedBundle: selected.path,
    nonselectedBundle: nonselected.path,
    primaryTarget: join(tempRoot, 'target-primary'),
    primaryReceipt: null,
    primarySummary: undefined,
  };
}

export function runInstallerTests(): InstallerTestReport {
  const results: InstallerCaseResult[] = [];
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-loa-installer-tests-'));
  try {
    let context: InstallerTestContext;
    try {
      context = prepareContext(tempRoot);
      results.push({ name: 'assemble and discover selected bundle', status: 'PASS' });
    } catch (error) {
      results.push({
        name: 'assemble and discover selected bundle',
        status: 'FAIL',
        error: error instanceof Error ? error.message : String(error),
      });
      return { result: 'FAIL', cases: results };
    }

    let alternateBundle = '';
    runCase(results, 'construct alternate verified update bundle', () => {
      alternateBundle = alternateVerifiedBundle(context);
    });

    runCase(results, 'fresh install exposes exact command skill launcher and verified bundle', () => {
      const installed = installLoaBundle(context.selectedBundle, context.primaryTarget);
      expectInstallationPass(installed, 'fresh installation');
      const verification = verifyLoaInstallation(context.primaryTarget);
      expectInstallationPass(verification, 'fresh installation verification');
      const bundleVerification = verifyBundle(installedRuntime(context.primaryTarget));
      expect(
        bundleVerification.result === 'PASS'
          && bundleVerification.summary?.id === LOA_BUNDLE_ID,
        `installed bundle failed verification: ${bundleVerification.errors.join('; ')}`,
      );
      assertExactExposure(context, COMMAND_SOURCE, COMMAND_DESTINATION);
      assertExactExposure(context, SKILL_SOURCE, SKILL_DESTINATION);
      assertExactExposure(context, LAUNCHER_SOURCE, LAUNCHER_DESTINATION);
      context.primaryReceipt = readFileSync(installRecordPath(context.primaryTarget));
      context.primarySummary = installed.summary;
    });

    runCase(results, 'idempotent reinstall preserves deterministic receipt', () => {
      expect(context.primaryReceipt !== null, 'fresh installation receipt is unavailable');
      expect(context.primarySummary !== undefined, 'fresh installation summary is unavailable');
      const reinstalled = installLoaBundle(context.selectedBundle, context.primaryTarget);
      expectInstallationPass(reinstalled, 'idempotent reinstallation');
      const after = readFileSync(installRecordPath(context.primaryTarget));
      expect(after.equals(context.primaryReceipt), 'idempotent reinstall changed receipt bytes');
      expect(
        canonicalSummary(reinstalled.summary) === canonicalSummary(context.primarySummary),
        'idempotent reinstall changed installation identity',
      );
    });

    runCase(results, 'two targets receive byte-identical deterministic receipts', () => {
      expect(context.primaryReceipt !== null, 'primary installation receipt is unavailable');
      expect(context.primarySummary !== undefined, 'primary installation summary is unavailable');
      const secondTarget = join(context.tempRoot, 'target-secondary');
      const installed = installLoaBundle(context.selectedBundle, secondTarget);
      expectInstallationPass(installed, 'secondary fresh installation');
      const receipt = readFileSync(installRecordPath(secondTarget));
      expect(receipt.equals(context.primaryReceipt), 'target path changed receipt bytes');
      expect(
        canonicalSummary(installed.summary) === canonicalSummary(context.primarySummary),
        'target path changed installation identity',
      );
    });

    runCase(results, 'tampered bundle is rejected before target mutation', () => {
      const bundle = join(context.tempRoot, 'bundle-tampered');
      const target = join(context.tempRoot, 'target-tampered-bundle');
      cloneBundle(context.selectedBundle, bundle);
      const commandPath = join(bundle, COMMAND_SOURCE);
      writeFileSync(commandPath, Buffer.concat([
        readFileSync(commandPath),
        Buffer.from('\ntampered\n', 'utf8'),
      ]));
      expect(verifyBundle(bundle).result === 'FAIL', 'tampered bundle still verifies');
      const installed = installLoaBundle(bundle, target);
      expectInstallationFail(installed, 'tampered bundle installation');
      assertNoInstallRecord(target);
    });

    runCase(results, 'tampered installed file fails verification and blocks update', () => {
      const target = join(context.tempRoot, 'target-tampered-installation');
      const installed = installLoaBundle(context.selectedBundle, target);
      expectInstallationPass(installed, 'tamper-case initial installation');
      const command = join(target, COMMAND_DESTINATION);
      const record = readFileSync(installRecordPath(target));
      const tampered = Buffer.concat([
        readFileSync(command),
        Buffer.from('\nlocally modified\n', 'utf8'),
      ]);
      writeFileSync(command, tampered);
      expectInstallationFail(
        verifyLoaInstallation(target),
        'tampered installation verification',
      );
      const update = installLoaBundle(context.selectedBundle, target);
      expectInstallationFail(update, 'update over tampered installation');
      expect(readFileSync(command).equals(tampered), 'refused update rewrote tampered file');
      expect(
        readFileSync(installRecordPath(target)).equals(record),
        'refused update rewrote installation receipt',
      );
    });

    runCase(results, 'verified nonselected adapter bundle is rejected by identity', () => {
      const target = join(context.tempRoot, 'target-nonselected');
      const verification = verifyBundle(context.nonselectedBundle);
      expect(
        verification.result === 'PASS',
        `nonselected bundle is not a valid control: ${verification.errors.join('; ')}`,
      );
      const installed = installLoaBundle(context.nonselectedBundle, target);
      expectInstallationFail(installed, 'nonselected bundle installation');
      assertNoInstallRecord(target);
    });

    runCase(results, 'self-resealed exposure absent from verified map is rejected', () => {
      const target = join(context.tempRoot, 'target-unmapped-exposure');
      const installed = installLoaBundle(context.selectedBundle, target);
      expectInstallationPass(installed, 'unmapped-exposure initial installation');
      const originalReceipt = readFileSync(installRecordPath(target));
      const { previous } = addStaleManagedExposure(target);
      writeFileSync(installRecordPath(target), canonicalJsonBytes(previous));
      expectInstallationFail(
        verifyLoaInstallation(target),
        'self-resealed unmapped exposure verification',
      );
      writeFileSync(installRecordPath(target), originalReceipt);
    });

    runCase(results, 'stale managed deletion removes exact prior bytes and preserves unmanaged siblings', () => {
      const target = join(context.tempRoot, 'target-stale-managed');
      const installed = installLoaBundle(context.selectedBundle, target);
      expectInstallationPass(installed, 'stale-case initial installation');
      const stale = addStaleManagedExposure(target);
      const unmanagedCommand = join(target, '.claude/commands/operator-owned.md');
      const unmanagedSkill = join(target, '.claude/skills/operator-owned/SKILL.md');
      mkdirSync(dirname(unmanagedCommand), { recursive: true });
      mkdirSync(dirname(unmanagedSkill), { recursive: true });
      writeFileSync(unmanagedCommand, 'operator command\n');
      writeFileSync(unmanagedSkill, 'operator skill\n');
      removeStaleManagedFiles(target, stale.previous, stale.next);
      expect(
        !existsSync(join(target, stale.staleDestination)),
        'stale managed exposure survived deletion',
      );
      expect(
        readFileSync(unmanagedCommand, 'utf8') === 'operator command\n',
        'unmanaged command sibling was changed',
      );
      expect(
        readFileSync(unmanagedSkill, 'utf8') === 'operator skill\n',
        'unmanaged skill sibling was changed',
      );
      expectInstallationPass(
        verifyLoaInstallation(target),
        'post-deletion installation verification',
      );
    });

    runCase(results, 'fresh-install interruptions recover on retry without exposing a runnable image', () => {
      for (const checkpoint of INTERRUPTION_POINTS) {
        const label = `fresh-${checkpoint}`;
        const target = join(context.tempRoot, `target-${label}`);
        const preserved = addPreservedState(target, label);
        const interrupted = installLoaBundle(context.selectedBundle, target, {
          testFault: { kind: 'interruption', after: checkpoint },
        });
        expectInstallationFail(interrupted, `${label} interruption`);
        expect(
          existsSync(join(target, TRANSACTION_PATH)),
          `${label} did not retain its recovery transaction`,
        );
        expectInstallationFail(
          verifyLoaInstallation(target),
          `${label} active-transaction verification`,
        );
        expectThrows(
          () => verifyInstalledLauncherRuntime(target),
          /transaction|recovery/iu,
          `${label} launcher guard`,
        );
        assertPreservedState(preserved, label);

        const retried = installLoaBundle(context.selectedBundle, target);
        expectInstallationPass(retried, `${label} retry`);
        expect(
          !existsSync(join(target, TRANSACTION_PATH)),
          `${label} retry left a permanent transaction wedge`,
        );
        expectInstallationPass(
          verifyLoaInstallation(target),
          `${label} recovered installation`,
        );
        verifyInstalledLauncherRuntime(target);
        assertPreservedState(preserved, label);
      }
    });

    runCase(results, 'update failure rolls back the prior image and preserves unmanaged state', () => {
      expect(alternateBundle !== '', 'alternate update bundle is unavailable');
      const label = 'update-failure';
      const target = join(context.tempRoot, `target-${label}`);
      expectInstallationPass(
        installLoaBundle(context.selectedBundle, target),
        `${label} initial installation`,
      );
      const preserved = addPreservedState(target, label);
      const priorReceipt = readFileSync(installRecordPath(target));
      const priorCommand = readFileSync(join(target, COMMAND_DESTINATION));
      const failed = installLoaBundle(alternateBundle, target, {
        testFault: { kind: 'failure', after: 'after-runtime-published' },
      });
      expectInstallationFail(failed, `${label} injected failure`);
      expect(
        !existsSync(join(target, TRANSACTION_PATH)),
        `${label} rollback left an active transaction`,
      );
      expect(
        readFileSync(installRecordPath(target)).equals(priorReceipt),
        `${label} rollback changed the prior receipt`,
      );
      expect(
        readFileSync(join(target, COMMAND_DESTINATION)).equals(priorCommand),
        `${label} rollback changed the prior command`,
      );
      expectInstallationPass(verifyLoaInstallation(target), `${label} rollback verification`);
      verifyInstalledLauncherRuntime(target);
      assertPreservedState(preserved, label);

      expectInstallationPass(
        installLoaBundle(alternateBundle, target),
        `${label} later update`,
      );
      expect(
        readFileSync(join(target, COMMAND_DESTINATION))
          .equals(readFileSync(join(alternateBundle, COMMAND_SOURCE))),
        `${label} later update did not publish the alternate command`,
      );
      assertPreservedState(preserved, label);
    });

    runCase(results, 'update interruptions restore then publish on retry at multiple checkpoints', () => {
      expect(alternateBundle !== '', 'alternate update bundle is unavailable');
      for (const checkpoint of INTERRUPTION_POINTS) {
        const label = `update-${checkpoint}`;
        const target = join(context.tempRoot, `target-${label}`);
        expectInstallationPass(
          installLoaBundle(context.selectedBundle, target),
          `${label} initial installation`,
        );
        const preserved = addPreservedState(target, label);
        const interrupted = installLoaBundle(alternateBundle, target, {
          testFault: { kind: 'interruption', after: checkpoint },
        });
        expectInstallationFail(interrupted, `${label} interruption`);
        expect(
          existsSync(join(target, TRANSACTION_PATH)),
          `${label} did not retain its recovery transaction`,
        );
        expectThrows(
          () => verifyInstalledLauncherRuntime(target),
          /transaction|recovery/iu,
          `${label} launcher guard`,
        );
        assertPreservedState(preserved, label);

        const retried = installLoaBundle(alternateBundle, target);
        expectInstallationPass(retried, `${label} retry`);
        expect(
          !existsSync(join(target, TRANSACTION_PATH)),
          `${label} retry left a permanent transaction wedge`,
        );
        expect(
          readFileSync(join(target, COMMAND_DESTINATION))
            .equals(readFileSync(join(alternateBundle, COMMAND_SOURCE))),
          `${label} retry did not publish the alternate command`,
        );
        expectInstallationPass(
          verifyLoaInstallation(target),
          `${label} recovered update verification`,
        );
        verifyInstalledLauncherRuntime(target);
        assertPreservedState(preserved, label);
      }
    });

    runCase(results, 'live writer serializes a competing install without recovering its transaction', () => {
      expect(alternateBundle !== '', 'alternate update bundle is unavailable');
      const target = join(context.tempRoot, 'target-live-install-writer');
      expectInstallationPass(
        installLoaBundle(context.selectedBundle, target),
        'live-writer initial installation',
      );
      const interrupted = installLoaBundle(alternateBundle, target, {
        testFault: { kind: 'interruption', after: 'after-runtime-published' },
      });
      expectInstallationFail(interrupted, 'live-writer interrupted update');
      const transactionRecord = join(target, TRANSACTION_PATH, 'transaction.json');
      const transactionBefore = readFileSync(transactionRecord);
      const commandWasPresent = existsSync(join(target, COMMAND_DESTINATION));
      const release = acquireLiveTestWriter(target);
      try {
        const blocked = installLoaBundle(alternateBundle, target);
        expectInstallationFail(blocked, 'concurrent installer invocation');
        expect(
          blocked.errors.some((error) => /writer.*already active/iu.test(error)),
          `concurrent installer omitted live-owner diagnostic: ${blocked.errors.join('; ')}`,
        );
        expect(
          readFileSync(transactionRecord).equals(transactionBefore),
          'concurrent installer changed the active transaction',
        );
        expect(
          existsSync(join(target, COMMAND_DESTINATION)) === commandWasPresent,
          'concurrent installer recovered or republished the active image',
        );
      } finally {
        release();
      }
      expectInstallationPass(
        installLoaBundle(alternateBundle, target),
        'live-writer recovery after release',
      );
      expect(!existsSync(join(target, TRANSACTION_PATH)), 'recovery left transaction state');
      expect(!existsSync(testWriterLockPath(target)), 'recovery left writer ownership');
    });

    runCase(results, 'dead writer ownership and interrupted update recover together', () => {
      expect(alternateBundle !== '', 'alternate update bundle is unavailable');
      const target = join(context.tempRoot, 'target-dead-install-writer');
      expectInstallationPass(
        installLoaBundle(context.selectedBundle, target),
        'dead-writer initial installation',
      );
      const interrupted = installLoaBundle(alternateBundle, target, {
        testFault: { kind: 'interruption', after: 'after-runtime-published' },
      });
      expectInstallationFail(interrupted, 'dead-writer interrupted update');
      expect(existsSync(join(target, TRANSACTION_PATH)), 'interrupted update left no transaction');
      leaveDeadTestWriter(target);
      expectInstallationPass(
        installLoaBundle(alternateBundle, target),
        'dead-writer recovered update',
      );
      expect(!existsSync(testWriterLockPath(target)), 'dead writer lock survived recovery');
      expect(!existsSync(join(target, TRANSACTION_PATH)), 'transaction survived recovery');
      expect(
        readFileSync(join(target, COMMAND_DESTINATION))
          .equals(readFileSync(join(alternateBundle, COMMAND_SOURCE))),
        'dead-writer recovery did not publish the requested update',
      );
      expectInstallationPass(
        verifyLoaInstallation(target),
        'dead-writer recovered installation verification',
      );
    });

    runCase(results, 'truncated writer ownership is safely recovered', () => {
      const target = join(context.tempRoot, 'target-truncated-install-writer');
      mkdirSync(join(target, '.claude'), { recursive: true });
      writeFileSync(testWriterLockPath(target), '{"pid":"2147483647"');
      expectInstallationPass(
        installLoaBundle(context.selectedBundle, target),
        'truncated-writer fresh installation',
      );
      expect(!existsSync(testWriterLockPath(target)), 'truncated writer ownership survived recovery');
      expectInstallationPass(
        verifyLoaInstallation(target),
        'truncated-writer installation verification',
      );
    });

    runCase(results, 'installer imports and operations remain offline-only', () => {
      assertInstallerHasNoNetworkImports();
    });
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
  return {
    result: results.every((result) => result.status === 'PASS') ? 'PASS' : 'FAIL',
    cases: results,
  };
}

function main(): void {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const help = args.includes('--help') || args.includes('-h');
  const unknown = args.filter((arg) => !['--json', '--help', '-h'].includes(arg));
  if (help) {
    console.log('Usage: node adapters/loa/tests/test-loa-installer.ts [--json]');
    process.exit(0);
  }
  if (unknown.length > 0) {
    console.error(`unknown argument ${unknown[0]}`);
    process.exit(2);
  }
  const report = runInstallerTests();
  if (json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    for (const result of report.cases) {
      console.log(
        `${result.status} LOA-INSTALLER ${result.name}`
        + (result.error ? `: ${result.error}` : ''),
      );
    }
    console.log(`RESULT: ${report.result}`);
  }
  process.exit(report.result === 'PASS' ? 0 : 1);
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) main();
