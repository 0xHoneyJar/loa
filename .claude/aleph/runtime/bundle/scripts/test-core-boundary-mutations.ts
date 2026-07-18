#!/usr/bin/env node

import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateCoreBoundary } from './validate-core-boundary.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');

interface CaseResult {
  name: string;
  expectedCheck: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

interface RebuildResult {
  name: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

interface MutationCase {
  name: string;
  expectedCheck: string;
  mutate: (root: string) => void;
}

const options = {
  json: false,
  help: false,
  error: '',
};

for (const arg of process.argv.slice(2)) {
  if (arg === '--json') options.json = true;
  else if (arg === '--help' || arg === '-h') options.help = true;
  else options.error = `unknown argument "${arg}"`;
}

function runGit(
  root: string,
  args: string[],
  env: Record<string, string> = {},
): string {
  const result = spawnSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
    env: {
      ...process.env,
      ...env,
    },
  });
  if (result.status !== 0) {
    throw new Error(
      `git ${args.join(' ')} failed: ${
        result.stderr.trim() || result.error?.message || `status ${String(result.status)}`
      }`,
    );
  }
  return result.stdout;
}

function sourceFiles(): string[] {
  const output = runGit(
    REPO_ROOT,
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
  );
  const deleted = new Set(
    runGit(REPO_ROOT, ['ls-files', '-z', '--deleted'])
      .split('\0')
      .filter(Boolean),
  );
  return output.split('\0').filter((path) => path && !deleted.has(path));
}

function copyRepository(root: string): void {
  for (const path of sourceFiles()) {
    const destination = join(root, path);
    mkdirSync(dirname(destination), { recursive: true });
    cpSync(join(REPO_ROOT, path), destination);
  }
  runGit(root, ['init', '-q']);
  runGit(root, ['add', '--all']);
  runGit(
    root,
    [
      '-c',
      'user.name=Aleph Core Boundary Tests',
      '-c',
      'user.email=aleph-core-boundary-tests.invalid',
      '-c',
      'commit.gpgsign=false',
      'commit',
      '-qm',
      'frozen Core-boundary test source',
    ],
    {
      GIT_AUTHOR_DATE: '2000-01-01T00:00:00Z',
      GIT_COMMITTER_DATE: '2000-01-01T00:00:00Z',
    },
  );
}

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>;
}

function writeJson(path: string, value: unknown): void {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function adapterManifest(
  root: string,
  adapterId: string,
): { path: string; value: Record<string, unknown> } {
  const path = join(root, 'adapters', adapterId, 'adapter.manifest.json');
  return { path, value: readJson(path) };
}

function promoteLoaToImplemented(
  root: string,
  runtimeRequirements: string[],
): void {
  const evidencePath = 'adapters/loa/implementation-evidence.txt';
  const { path, value } = adapterManifest(root, 'loa');
  const adapter = value.adapter as Record<string, unknown>;
  adapter.version = '0.1.0';
  adapter.lifecycle = 'implemented';

  const entrypoints = value.entrypoints as Array<Record<string, unknown>>;
  for (const entrypoint of entrypoints) {
    entrypoint.state = 'implemented';
    entrypoint.path = evidencePath;
  }
  const installation = value.installation as Record<string, unknown>;
  installation.state = 'implemented';
  installation.path = evidencePath;

  const capabilities = value.capabilities as Record<string, Record<string, unknown>>;
  for (const capability of Object.values(capabilities)) {
    capability.state = 'implemented';
    capability.evidence = [evidencePath];
  }
  (value.full_mode as Record<string, unknown>).claimed = true;
  value.profiles = [{
    id: 'default',
    state: 'implemented',
    path: evidencePath,
    runtime_requirements: runtimeRequirements,
    model_mapping: {},
    effort_mapping: {},
    evidence: [evidencePath],
  }];
  const evidence = value.evidence as Record<string, unknown>;
  evidence.implementation = [evidencePath];
  evidence.validation = [];
  evidence.sanction = [];
  (value.owned_paths as string[]).push(evidencePath);

  const corePath = join(root, 'core.manifest.json');
  const core = readJson(corePath);
  const files = core.files as Record<string, unknown>;
  const adapters = files.adapter as Record<string, string[]>;
  adapters.loa.push(evidencePath);

  writeFileSync(join(root, evidencePath), 'temporary implementation evidence\n');
  writeJson(path, value);
  writeJson(corePath, core);
  runGit(root, ['add', '--all']);
}

const cases: MutationCase[] = [
  {
    name: 'Loa references Hermes',
    expectedCheck: 'CB8',
    mutate: (root) => {
      const { path, value } = adapterManifest(root, 'loa');
      const references = value.references as string[];
      references.push('adapters/hermes/adapter.manifest.json');
      writeJson(path, value);
    },
  },
  {
    name: 'adapter overrides Core',
    expectedCheck: 'CB7',
    mutate: (root) => {
      const { path, value } = adapterManifest(root, 'loa');
      const consumption = value.core_consumption as Record<string, unknown>;
      const overrides = consumption.overrides as string[];
      overrides.push('README.md');
      writeJson(path, value);
    },
  },
  {
    name: 'unclassified tracked file',
    expectedCheck: 'CB2',
    mutate: (root) => {
      writeFileSync(join(root, 'UNCLASSIFIED.txt'), 'must be classified\n');
      runGit(root, ['add', 'UNCLASSIFIED.txt']);
    },
  },
  {
    name: 'adapter claims sanctioned without matching evidence',
    expectedCheck: 'CB6',
    mutate: (root) => {
      const { path, value } = adapterManifest(root, 'loa');
      const adapter = value.adapter as Record<string, unknown>;
      adapter.lifecycle = 'sanctioned';
      writeJson(path, value);
    },
  },
  {
    name: 'schema-invalid entrypoint kind',
    expectedCheck: 'CB5',
    mutate: (root) => {
      const { path, value } = adapterManifest(root, 'loa');
      const entrypoints = value.entrypoints as Array<Record<string, unknown>>;
      entrypoints[0].kind = 'not-a-real-kind';
      writeJson(path, value);
    },
  },
  {
    name: 'schema-invalid adapter version',
    expectedCheck: 'CB5',
    mutate: (root) => {
      const { path, value } = adapterManifest(root, 'loa');
      const adapter = value.adapter as Record<string, unknown>;
      adapter.version = 'definitely malformed';
      writeJson(path, value);
    },
  },
  {
    name: 'Loa profile requires Hermes runtime',
    expectedCheck: 'CB8',
    mutate: (root) => {
      promoteLoaToImplemented(root, ['requires Hermes runtime']);
    },
  },
];

function execute(): {
  result: 'PASS' | 'FAIL';
  baseline: 'PASS' | 'FAIL';
  cases: CaseResult[];
  rebuilds: RebuildResult[];
} {
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-core-boundary-mutations-'));
  const caseResults: CaseResult[] = [];
  const rebuildResults: RebuildResult[] = [];
  let baseline: 'PASS' | 'FAIL' = 'FAIL';
  try {
    const baselineRoot = join(tempRoot, 'baseline');
    mkdirSync(baselineRoot, { recursive: true });
    copyRepository(baselineRoot);
    const baselineReport = validateCoreBoundary({ root: baselineRoot });
    baseline = baselineReport.result;
    if (baseline !== 'PASS') {
      const failures = baselineReport.checks
        .filter((check) => check.status === 'FAIL')
        .map((check) => `${check.id} ${check.message}`)
        .join('; ');
      throw new Error(`clean baseline failed: ${failures}`);
    }

    for (const [index, mutation] of cases.entries()) {
      const root = join(tempRoot, `${String(index + 1).padStart(2, '0')}`);
      mkdirSync(root, { recursive: true });
      try {
        copyRepository(root);
        mutation.mutate(root);
        const report = validateCoreBoundary({ root });
        const intended = report.checks.some((check) => (
          check.id === mutation.expectedCheck && check.status === 'FAIL'
        ));
        if (report.result !== 'FAIL' || !intended) {
          const failures = report.checks
            .filter((check) => check.status === 'FAIL')
            .map((check) => check.id)
            .join(', ');
          throw new Error(
            `expected FAIL ${mutation.expectedCheck}; result=${report.result}, `
            + `failing checks=${failures || 'none'}`,
          );
        }
        caseResults.push({
          name: mutation.name,
          expectedCheck: mutation.expectedCheck,
          status: 'PASS',
        });
      } catch (error) {
        caseResults.push({
          name: mutation.name,
          expectedCheck: mutation.expectedCheck,
          status: 'FAIL',
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const hermesOnlyRoot = join(tempRoot, 'rebuild-hermes-only');
    mkdirSync(hermesOnlyRoot, { recursive: true });
    try {
      copyRepository(hermesOnlyRoot);
      const hermesPath = join(
        hermesOnlyRoot,
        'adapters/hermes/adapter.manifest.json',
      );
      writeFileSync(hermesPath, `${readFileSync(hermesPath, 'utf8')}\n`);
      const changed = validateCoreBoundary({ root: hermesOnlyRoot });
      const unchangedLoa = (
        changed.result === 'PASS'
        && changed.digests.core === baselineReport.digests.core
        && changed.digests.checker === baselineReport.digests.checker
        && changed.digests.adapters.loa === baselineReport.digests.adapters.loa
        && changed.digests.bundles['aleph-for-loa']?.bundleDigest
          === baselineReport.digests.bundles['aleph-for-loa']?.bundleDigest
      );
      const changedHermes = (
        changed.digests.adapters.hermes !== baselineReport.digests.adapters.hermes
        && changed.digests.bundles['aleph-for-hermes']?.bundleDigest
          !== baselineReport.digests.bundles['aleph-for-hermes']?.bundleDigest
      );
      if (!unchangedLoa || !changedHermes) {
        throw new Error('Hermes-only bytes did not rebuild exactly the Hermes bundle');
      }
      rebuildResults.push({
        name: 'Hermes-only change rebuilds only Hermes',
        status: 'PASS',
      });
    } catch (error) {
      rebuildResults.push({
        name: 'Hermes-only change rebuilds only Hermes',
        status: 'FAIL',
        error: error instanceof Error ? error.message : String(error),
      });
    }

    const coreChangeRoot = join(tempRoot, 'rebuild-core');
    mkdirSync(coreChangeRoot, { recursive: true });
    try {
      copyRepository(coreChangeRoot);
      const corePath = join(coreChangeRoot, 'README.md');
      writeFileSync(corePath, `${readFileSync(corePath, 'utf8')}\n`);
      const changed = validateCoreBoundary({ root: coreChangeRoot });
      const changedBoth = (
        changed.result === 'PASS'
        && changed.digests.core !== baselineReport.digests.core
        && changed.digests.adapters.loa === baselineReport.digests.adapters.loa
        && changed.digests.adapters.hermes === baselineReport.digests.adapters.hermes
        && changed.digests.bundles['aleph-for-loa']?.bundleDigest
          !== baselineReport.digests.bundles['aleph-for-loa']?.bundleDigest
        && changed.digests.bundles['aleph-for-hermes']?.bundleDigest
          !== baselineReport.digests.bundles['aleph-for-hermes']?.bundleDigest
      );
      if (!changedBoth) {
        throw new Error('Core byte change did not rebuild both host bundles');
      }
      rebuildResults.push({
        name: 'Core change rebuilds both host bundles',
        status: 'PASS',
      });
    } catch (error) {
      rebuildResults.push({
        name: 'Core change rebuilds both host bundles',
        status: 'FAIL',
        error: error instanceof Error ? error.message : String(error),
      });
    }
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
  return {
    result: baseline === 'PASS'
      && caseResults.every((item) => item.status === 'PASS')
      && rebuildResults.every((item) => item.status === 'PASS')
      ? 'PASS'
      : 'FAIL',
    baseline,
    cases: caseResults,
    rebuilds: rebuildResults,
  };
}

function main(): void {
  if (options.help) {
    console.log('Usage: node scripts/test-core-boundary-mutations.ts [--json]');
    process.exit(0);
  }
  if (options.error) {
    console.error(options.error);
    process.exit(2);
  }
  try {
    const report = execute();
    if (options.json) {
      console.log(JSON.stringify(report, null, 2));
    } else {
      console.log(`${report.baseline} baseline clean repository`);
      for (const result of report.cases) {
        console.log(
          `${result.status} ${result.expectedCheck} ${result.name}`
          + (result.error ? `: ${result.error}` : ''),
        );
      }
      for (const result of report.rebuilds) {
        console.log(
          `${result.status} REBUILD ${result.name}`
          + (result.error ? `: ${result.error}` : ''),
        );
      }
      console.log(`RESULT: ${report.result}`);
    }
    process.exit(report.result === 'PASS' ? 0 : 1);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (options.json) {
      console.log(JSON.stringify({ result: 'FAIL', error: message }, null, 2));
    } else {
      console.error(`FAIL ${message}`);
      console.log('RESULT: FAIL');
    }
    process.exit(1);
  }
}

main();
