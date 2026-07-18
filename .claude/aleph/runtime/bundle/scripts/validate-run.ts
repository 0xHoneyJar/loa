#!/usr/bin/env node

import { existsSync, lstatSync, readFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runK2 } from './lib/checks-k2.ts';
import { runK3, runK4K5, runK6 } from './lib/checks-k3-k6.ts';
import { parseFencedBlock } from './lib/markdown.ts';
import { ResultCollector } from './lib/results.ts';
import type { CheckReport } from './lib/results.ts';
import { loadRun } from './lib/run-model.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const KINDS = new Set<RunKind>(['run', 'evidence-role', 'routed', 'projection']);

type RunKind = 'run' | 'evidence-role' | 'routed' | 'projection';

export interface ValidateRunOptions {
  root?: string;
  run?: string;
  kind?: RunKind | string;
}

interface RunReportExtra {
  scope: string;
  runDir: string;
  kind: string;
}

export type RunReport = CheckReport<RunReportExtra>;

interface CliOptions {
  root: string;
  run: string;
  kind: string;
  json: boolean;
  help: boolean;
  error?: string;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isRunKind(value: string): value is RunKind {
  return KINDS.has(value as RunKind);
}

function declarationKind(runDir: string): string {
  const path = join(runDir, 'README.md');
  if (!existsSync(path)) return '';
  const block = parseFencedBlock(readFileSync(path, 'utf8'), 'aleph-fixture');
  if (!block) return '';
  for (const line of block.split('\n')) {
    const match = line.match(/^\s*kind\s*:\s*([a-z-]+)/i);
    if (match) return match[1].toLowerCase();
  }
  return '';
}

function failureReport(
  scope: string,
  id: string,
  label: string,
  message: string,
  extra: Omit<RunReportExtra, 'scope'>,
): RunReport {
  return {
    result: 'FAIL',
    checks: [{
      id,
      scope,
      status: 'FAIL',
      message: `(${label}): ${message}`,
    }],
    scope,
    ...extra,
  };
}

/**
 * Validate one Aleph run or run-lite fixture without printing, exiting, writing,
 * spawning, or using the network.
 *
 * The public function stays import-safe and reports malformed input instead of
 * throwing or exiting.
 */
export function validateRun(options: ValidateRunOptions = {}): RunReport {
  const root = resolve(options.root || DEFAULT_ROOT);
  if (!options.run || typeof options.run !== 'string') {
    return failureReport('run', 'K2.1', 'layout', '--run is required', {
      runDir: '',
      kind: options.kind || 'run',
    });
  }
  const runDir = resolve(isAbsolute(options.run) ? options.run : join(root, options.run));
  const initialScope = basename(runDir) || 'run';
  if (!existsSync(runDir) || !lstatSync(runDir).isDirectory()) {
    return failureReport(initialScope, 'K2.1', 'layout', `run directory not found at ${runDir}`, {
      runDir,
      kind: options.kind || 'run',
    });
  }

  const kind = options.kind || declarationKind(runDir) || 'run';
  if (!isRunKind(kind)) {
    return failureReport(initialScope, 'K1.2', 'unknown kind', `kind "${kind}" is not supported by validate-run.ts`, {
      runDir,
      kind,
    });
  }

  let model: ReturnType<typeof loadRun>;
  try {
    model = loadRun(runDir);
  } catch (error) {
    return failureReport(initialScope, 'K2.1', 'layout', `could not read run tree: ${errorMessage(error)}`, {
      runDir,
      kind,
    });
  }
  const scope = model.manifest?.runId || initialScope;
  const results = new ResultCollector(scope);

  if (kind === 'run') {
    runK2(results, model, root);
    if (model.evidenceDocument) runK3(results, model);
    if (model.cards.length > 0 || model.referentDocument) runK4K5(results, model);
    const reachedProjection = Boolean(model.manifest?.states.some((row) => (
      ['PROJECTING', 'PROJECTION-ACCEPTED'].includes(row.values.state.trim())
    )));
    if (model.projections.length > 0 || reachedProjection) runK6(results, model);
  } else if (kind === 'evidence-role') {
    runK3(results, model);
  } else if (kind === 'routed') {
    runK4K5(results, model);
  } else if (kind === 'projection') {
    runK6(results, model);
  }

  return results.report({ scope, runDir, kind });
}

function parseArgs(argv: string[]): CliOptions {
  const options: CliOptions = {
    root: DEFAULT_ROOT,
    run: '',
    kind: '',
    json: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--json') {
      options.json = true;
    } else if (arg === '--root') {
      options.root = argv[++index] || '';
    } else if (arg.startsWith('--root=')) {
      options.root = arg.slice('--root='.length);
    } else if (arg === '--run') {
      options.run = argv[++index] || '';
    } else if (arg.startsWith('--run=')) {
      options.run = arg.slice('--run='.length);
    } else if (arg === '--kind') {
      options.kind = argv[++index] || '';
    } else if (arg.startsWith('--kind=')) {
      options.kind = arg.slice('--kind='.length);
    } else {
      options.error = `unknown argument "${arg}"`;
      break;
    }
  }
  return options;
}

function printHuman(report: RunReport): void {
  console.log('Aleph Run Conformance Kernel');
  console.log(`(run: ${report.runDir || '(missing)'}, kind: ${report.kind})`);
  console.log('');
  console.log('PASSED CHECKS:');
  for (const check of report.checks.filter((record) => record.status === 'PASS')) {
    console.log(`PASS ${check.scope} ${check.id} ${check.message}`);
  }
  const failures = report.checks.filter((record) => record.status === 'FAIL');
  if (failures.length > 0) {
    console.log('');
    console.log('FAILURES:');
    for (const check of failures) {
      console.log(`FAIL ${check.scope} ${check.id} ${check.message}`);
    }
  }
  console.log('');
  console.log(`RESULT: ${report.result}${failures.length ? ` (${failures.length} failure${failures.length === 1 ? '' : 's'})` : ''}`);
}

function main(): number {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('Usage: node scripts/validate-run.ts [--root DIR] --run PATH [--kind KIND] [--json]');
    return 0;
  }
  let report;
  if (args.error) {
    report = failureReport('run', 'K2.1', 'layout', args.error, {
      runDir: '',
      kind: args.kind || 'run',
    });
  } else {
    report = validateRun({
      root: args.root,
      run: args.run,
      kind: args.kind || undefined,
    });
  }
  if (args.json) {
    console.log(JSON.stringify({ result: report.result, checks: report.checks }));
  } else {
    printHuman(report);
  }
  return report.result === 'PASS' ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  process.exitCode = main();
}
