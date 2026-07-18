#!/usr/bin/env node

import {
  appendFileSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import type { SpawnSyncReturns } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const FIXTURES = join(REPO_ROOT, 'docs', 'fixtures');
const PRECIS_CHECKER = join(REPO_ROOT, 'scripts', 'validate-precis-fixtures.ts');
const RUN_CHECKER = join(REPO_ROOT, 'scripts', 'validate-run.ts');
const EXPECTED_CASES = new Map<string, number>([
  ['K1', 5],
  ['K2', 22],
  ['K3', 8],
  ['K4/K5', 9],
  ['K6', 11],
]);

const options = {
  json: false,
  help: false,
  error: '',
};

type CheckStatus = 'PASS' | 'FAIL';

interface CheckRecord {
  id: string;
  status: CheckStatus;
  message: string;
}

interface CheckerReport {
  result: CheckStatus;
  checks?: CheckRecord[];
}

interface MutationCase {
  group: string;
  name: string;
  execute: (root: string) => void;
}

interface BaselineResult {
  name: string;
  status: CheckStatus;
  error?: string;
}

interface CaseResult {
  group: string;
  name: string;
  status: CheckStatus;
  error?: string;
}

type FixtureMutation = (fixturePath: string, root: string) => void;

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
for (const arg of process.argv.slice(2)) {
  if (arg === '--json') options.json = true;
  else if (arg === '--help' || arg === '-h') options.help = true;
  else options.error = `unknown argument "${arg}"`;
}

if (options.help) {
  console.log('Usage: node scripts/test-conformance-mutations.ts [--json]');
  process.exit(0);
}
if (options.error) {
  console.error(options.error);
  process.exit(2);
}

const cases: MutationCase[] = [];
const baselineResults: BaselineResult[] = [];
const caseResults: CaseResult[] = [];
const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-conformance-mutations-'));
let sandboxCounter = 0;

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function sandbox(label: string): string {
  sandboxCounter += 1;
  const path = join(
    tempRoot,
    `${String(sandboxCounter).padStart(2, '0')}-${slug(label)}`,
  );
  mkdirSync(path, { recursive: true });
  return path;
}

function copyFixture(
  name: string,
  root: string,
  relativePath = join('docs', 'fixtures', name),
): string {
  const destination = join(root, relativePath);
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(join(FIXTURES, name), destination, { recursive: true });
  return destination;
}

function copyLegacyFixtures(root: string): void {
  copyFixture('slice-1', root);
  copyFixture('slice-2', root);
}

function replaceOnce(path: string, before: string, after: string): void {
  const text = readFileSync(path, 'utf8');
  const first = text.indexOf(before);
  if (first < 0) {
    throw new Error(`${path} does not contain the mutation target ${JSON.stringify(before)}`);
  }
  writeFileSync(path, `${text.slice(0, first)}${after}${text.slice(first + before.length)}`);
}

function replaceRegexOnce(
  path: string,
  pattern: RegExp,
  replacement: string,
): void {
  if (pattern.global) throw new Error('replaceRegexOnce requires a non-global RegExp');
  const text = readFileSync(path, 'utf8');
  if (!pattern.test(text)) {
    throw new Error(`${path} does not match mutation pattern ${pattern}`);
  }
  writeFileSync(path, text.replace(pattern, replacement));
}

function removeLine(path: string, pattern: RegExp): void {
  if (pattern.global) throw new Error('removeLine requires a non-global RegExp');
  const text = readFileSync(path, 'utf8');
  const lines = text.split('\n');
  const index = lines.findIndex((line) => pattern.test(line));
  if (index < 0) throw new Error(`${path} has no line matching ${pattern}`);
  lines.splice(index, 1);
  writeFileSync(path, lines.join('\n'));
}

function invoke(script: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: REPO_ROOT,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
}

function reportFrom(result: SpawnSyncReturns<string>): CheckerReport {
  if (result.error) throw result.error;
  const output = result.stdout.trim();
  if (!output) {
    throw new Error(
      `checker produced no JSON (status ${result.status}; stderr: ${result.stderr.trim() || 'empty'})`,
    );
  }
  try {
    return JSON.parse(output) as CheckerReport;
  } catch (error) {
    throw new Error(
      `checker output is not JSON: ${errorMessage(error)}; stdout: ${output.slice(0, 500)}`,
    );
  }
}

function requireCheck(
  report: CheckerReport,
  id: string,
  status: CheckStatus,
  messagePattern: RegExp | null = null,
): CheckRecord {
  const record = report.checks?.find((check) => (
    check.id === id
    && check.status === status
    && (!messagePattern || messagePattern.test(check.message))
  ));
  if (!record) {
    const seen = (report.checks || [])
      .filter((check) => check.status === status)
      .map((check) => check.id)
      .join(', ');
    throw new Error(
      `expected ${status} ${id}${messagePattern ? ` matching ${messagePattern}` : ''}; `
      + `${status} ids were ${seen || 'none'}`,
    );
  }
  return record;
}

function requireFailure(result: SpawnSyncReturns<string>, id: string): CheckerReport {
  const report = reportFrom(result);
  if (result.status === 0 || report.result !== 'FAIL') {
    throw new Error(`expected nonzero/FAIL for ${id}, got status ${result.status}/${report.result}`);
  }
  requireCheck(report, id, 'FAIL');
  return report;
}

function requireOutputOmits(result: SpawnSyncReturns<string>, token: string): void {
  const combinedOutput = `${result.stdout}\n${result.stderr}`.toLowerCase();
  if (combinedOutput.includes(token.toLowerCase())) {
    throw new Error(`checker output exposed a redacted forbidden token`);
  }
}

function requirePass(
  result: SpawnSyncReturns<string>,
  ids: readonly string[] = [],
  messagePatterns: ReadonlyMap<string, RegExp> = new Map(),
): CheckerReport {
  const report = reportFrom(result);
  if (result.status !== 0 || report.result !== 'PASS') {
    const failed = (report.checks || [])
      .filter((check) => check.status === 'FAIL')
      .map((check) => `${check.id}: ${check.message}`)
      .join('; ');
    throw new Error(
      `expected zero/PASS, got status ${result.status}/${report.result}`
      + (failed ? `; ${failed}` : ''),
    );
  }
  for (const id of ids) {
    requireCheck(report, id, 'PASS', messagePatterns.get(id) || null);
  }
  return report;
}

function runPrecis(root: string): SpawnSyncReturns<string> {
  return invoke(PRECIS_CHECKER, ['--root', root, '--json']);
}

function expectedLegacyHumanOutput(root: string): string {
  const passMessages = [
    'discovery: 2 fixture directories recognized; declarations valid',
    'slice-1 files: exactly README.md, corpus.md, precis.md present; Markdown-only',
    'slice-1 forbidden tokens: zero configured absolute-forbidden occurrences',
    'slice-1 projection boundary: no downstream-projection generation / no real-export markers',
    'slice-1 schema wording: explicitly rejects schema finality (provisional v0)',
    'slice-1 corpus boundary: source IDs present; no answer-key/label leakage',
    'slice-1 envelope: all 17 accepted provisional v0 sections present',
    'slice-1 inventory & accounting: 10 unique claims, each exactly one valid disposition, all 7 dispositions covered, ledger balances (10=10)',
    'slice-1 cross-section consistency: no phantom/orphan CC·SRC·STM refs, §5↔§4 dispositions agree, matrix refs resolve, merge provenance retained (C1–C8)',
    'slice-2 files: exactly README.md, corpus.md, precis.md present; Markdown-only',
    'slice-2 forbidden tokens: zero configured absolute-forbidden occurrences',
    'slice-2 projection boundary: no downstream-projection generation / no real-export markers',
    'slice-2 schema wording: explicitly rejects schema finality (provisional v0)',
    'slice-2 corpus boundary: source IDs present; no answer-key/label leakage',
    'slice-2 envelope: all 17 accepted provisional v0 sections present',
    'slice-2 inventory & accounting: 14 unique claims, each exactly one valid disposition, all 7 dispositions covered, ledger balances (14=14)',
    'slice-2 matrix: stress-test matrix section present with table rows STM-1..STM-7 (each once)',
    'slice-2 cross-section consistency: no phantom/orphan CC·SRC·STM refs, §5↔§4 dispositions agree, matrix refs resolve, merge provenance retained (C1–C8)',
  ];
  return [
    'Aleph Précis Conformance Checker — v0 envelope (Slice 3) + cross-section consistency (Slice 4)',
    '(validates the accepted provisional v0 envelope; this is NOT a schema freeze)',
    `(root override: ${root})`,
    '',
    'PASSED CHECKS:',
    ...passMessages.map((message) => `  PASS ${message}`),
    '',
    'RESULT: PASS — both fixtures conform to the accepted provisional v0 envelope.',
    '',
  ].join('\n');
}

function requireLegacyHumanOutput(result: SpawnSyncReturns<string>, root: string): void {
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `expected legacy human checker to exit zero, got ${result.status}; `
      + `stderr: ${result.stderr.trim() || 'empty'}`,
    );
  }
  if (result.stderr !== '') {
    throw new Error(`expected empty stderr, got ${JSON.stringify(result.stderr)}`);
  }

  const expected = expectedLegacyHumanOutput(root);
  if (result.stdout === expected) return;

  let offset = 0;
  const limit = Math.min(result.stdout.length, expected.length);
  while (offset < limit && result.stdout[offset] === expected[offset]) offset++;
  throw new Error(
    `legacy human output differs at byte ${offset}; `
    + `expected ${JSON.stringify(expected.slice(offset, offset + 120))}, `
    + `got ${JSON.stringify(result.stdout.slice(offset, offset + 120))}`,
  );
}

function runFixture(root: string, relativePath: string): SpawnSyncReturns<string> {
  return invoke(RUN_CHECKER, [
    '--root',
    root,
    '--run',
    relativePath,
    '--json',
  ]);
}

function addCase(group: string, name: string, execute: MutationCase['execute']): void {
  cases.push({ group, name, execute });
}

function addFailureCase(
  group: string,
  name: string,
  fixture: string,
  expectedId: string,
  mutate: FixtureMutation,
): void {
  addCase(group, name, (root) => {
    const relativePath = join('docs', 'fixtures', fixture);
    const fixturePath = copyFixture(fixture, root, relativePath);
    mutate(fixturePath, root);
    requireFailure(runFixture(root, relativePath), expectedId);
  });
}

function runBaseline(name: string, fixture: string, ids: readonly string[]): void {
  const root = sandbox(`baseline-${name}`);
  const relativePath = join('docs', 'fixtures', fixture);
  try {
    copyFixture(fixture, root, relativePath);
    requirePass(runFixture(root, relativePath), ids);
    baselineResults.push({ name, status: 'PASS' });
    if (!options.json) console.log(`PASS baseline ${name}`);
  } catch (error) {
    const message = errorMessage(error);
    baselineResults.push({ name, status: 'FAIL', error: message });
    if (!options.json) console.log(`FAIL baseline ${name}: ${message}`);
  }
}

// K1: four negative discovery/dispatch cases plus the required legacy lock.
addCase('K1', 'missing fixture declaration', (root) => {
  copyLegacyFixtures(root);
  const path = join(root, 'docs', 'fixtures', 'undeclared');
  mkdirSync(path, { recursive: true });
  writeFileSync(join(path, 'README.md'), '# Undeclared fixture\n');
  requireFailure(runPrecis(root), 'K1.1');
});

addCase('K1', 'declared range drives existing inventory checks', (root) => {
  copyLegacyFixtures(root);
  const path = copyFixture('slice-1', root, join('docs', 'fixtures', 'declared-precis'));
  appendFileSync(
    join(path, 'README.md'),
    '\n```aleph-fixture\n'
      + 'kind: precis\n'
      + 'src_ids: SRC-001..SRC-003\n'
      + 'cc_ids: CC-001..CC-009\n'
      + 'ledger_total: 10\n'
      + '```\n',
  );
  requireFailure(runPrecis(root), 'P7');
});

addCase('K1', 'unknown fixture kind', (root) => {
  copyLegacyFixtures(root);
  const path = join(root, 'docs', 'fixtures', 'unknown-kind');
  mkdirSync(path, { recursive: true });
  writeFileSync(
    join(path, 'README.md'),
    '# Unknown fixture\n\n```aleph-fixture\nkind: mystery\n```\n',
  );
  requireFailure(runPrecis(root), 'K1.2');
});

addCase('K1', 'malformed declared range', (root) => {
  copyLegacyFixtures(root);
  const path = join(root, 'docs', 'fixtures', 'bad-range');
  mkdirSync(path, { recursive: true });
  writeFileSync(
    join(path, 'README.md'),
    '# Bad range fixture\n\n'
      + '```aleph-fixture\n'
      + 'kind: evidence-role\n'
      + 'cc_ids: CC-001..SRC-003\n'
      + '```\n',
  );
  requireFailure(runPrecis(root), 'K1.3');
});

addCase('K1', 'legacy slices remain green', (root) => {
  copyLegacyFixtures(root);
  requirePass(runPrecis(root), ['K1']);
  requireLegacyHumanOutput(
    invoke(PRECIS_CHECKER, ['--root', root]),
    root,
  );
  const deferredBusinessIntelligenceConsumerName = ['sense', 'net'].join('');
  appendFileSync(
    join(root, 'docs', 'fixtures', 'slice-1', 'README.md'),
    `\nForbidden deferred-consumer name: ${deferredBusinessIntelligenceConsumerName}\n`,
  );
  const forbiddenResult = runPrecis(root);
  requireFailure(forbiddenResult, 'P2');
  requireOutputOmits(forbiddenResult, deferredBusinessIntelligenceConsumerName);
});

// K2: one case per K2.1-K2.11, plus complete structured-ID family coverage.
// K2.3 proves both sides of fixture scoping.
addCase('K2', 'top-level adapter control is outside canonical discovery', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  const runtime = join(path, 'control', 'runtime', 'bundle');
  mkdirSync(runtime, { recursive: true });
  writeFileSync(
    join(runtime, 'run-manifest.md'),
    '# Retained runtime bytes\n\n'
      + 'Fixture-only token: Phase\n'
      + 'Canonical-looking but adapter-owned IDs: RUN-shadow CC-999.\n',
  );

  requirePass(runFixture(root, relativePath), ['K2.3', 'K2.5']);

  const nestedControl = join(path, 'verification', 'control', 'canonical.md');
  mkdirSync(dirname(nestedControl), { recursive: true });
  writeFileSync(nestedControl, 'Canonical nested control ID: RUN-shadow.\n');
  requireFailure(runFixture(root, relativePath), 'K2.5');
  rmSync(nestedControl);

  appendFileSync(join(path, 'run-log.md'), '\nCanonical dangling ID: RUN-shadow.\n');
  requireFailure(runFixture(root, relativePath), 'K2.5');
});

addCase('K2', 'CORPUS-FROZEN excludes future-stage artifacts', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  for (const entry of [
    'README.md',
    'arms',
    'clusters',
    'ledgers',
    'precis.md',
    'projections',
    'synthesis',
    'verification',
  ]) {
    rmSync(join(path, entry), { recursive: true, force: true });
  }
  writeFileSync(
    join(path, 'run-manifest.md'),
    '# Run Manifest — RUN-slice-2\n\n'
      + '## Identity\n\n'
      + '- run_id: RUN-slice-2\n'
      + '- predecessor_run: none\n'
      + '- mode: manual\n'
      + '- doctrine_sha: 2dc3549a0c6f3fed660b10743198409945c70b64\n\n'
      + '## Corpus binding\n\n'
      + '- corpus_ref: corpus/manifest.md\n'
      + '- corpus_hash: sha256:ccf27103ab6e9855057688bd861df942feec1597fde0283932bbbcc4f2f606a1\n\n'
      + '## State log\n\n'
      + '| # | state | entered | actor | note |\n'
      + '|---|-------|---------|-------|------|\n'
      + '| 1 | DRAFT | 2026-07-16 08:00 UTC | manual-fixture-coordinator | run directory created |\n'
      + '| 2 | CORPUS-FROZEN | 2026-07-16 08:20 UTC | fixture-simulated authority | corpus frozen |\n\n'
      + '## Authority sign-offs\n\n'
      + '| gate | decision | by | date | reference |\n'
      + '|------|----------|----|------|-----------|\n'
      + '| S0 corpus scope + sensitivity | fixture-simulated approved | fixture-simulated authority | 2026-07-16 | run-log.md S0 gate entry |\n',
  );
  writeFileSync(
    join(path, 'run-log.md'),
    '# Run Log — RUN-slice-2\n\n'
      + '## 2026-07-16 08:00 UTC — S0 — entry\n\n'
      + 'The run directory was created.\n\n'
      + '## 2026-07-16 08:20 UTC — S0 — exit\n\n'
      + 'The corpus was frozen.\n',
  );

  const patterns = new Map([
    ['K2.6', /not applicable before DISTILLING/],
    ['K2.9', /not applicable before DISTILLING/],
  ]);
  requirePass(runFixture(root, relativePath), ['K2.1', 'K2.6', 'K2.9'], patterns);

  replaceOnce(
    join(path, 'run-manifest.md'),
    '| 2 | CORPUS-FROZEN | 2026-07-16 08:20 UTC | fixture-simulated authority | corpus frozen |',
    '| 2 | CORPUS-FROZEN | 2026-07-16 08:20 UTC | fixture-simulated authority | corpus frozen |\n'
      + '| 3 | DISTILLING | 2026-07-16 08:30 UTC | manual-runner | distillation began |',
  );
  requireFailure(runFixture(root, relativePath), 'K2.1');
});

addFailureCase('K2', 'missing run manifest', 'run-slice-2', 'K2.1', (path) => {
  rmSync(join(path, 'run-manifest.md'));
});

addFailureCase('K2', 'invalid state transition', 'run-slice-2', 'K2.2', (path) => {
  replaceOnce(
    join(path, 'run-manifest.md'),
    '| 2 | CORPUS-FROZEN |',
    '| 2 | ASSEMBLED |',
  );
});

addFailureCase('K2', 'malformed predecessor run', 'run-slice-2', 'K2.2', (path) => {
  replaceOnce(
    join(path, 'run-manifest.md'),
    '- predecessor_run: none',
    '- predecessor_run: prior-run',
  );
});

addFailureCase('K2', 'duplicate run id field', 'run-slice-2', 'K2.2', (path) => {
  replaceOnce(
    join(path, 'run-manifest.md'),
    '- run_id: RUN-slice-2',
    '- run_id: RUN-slice-2\n- run_id: RUN-shadow',
  );
});

addCase('K2', 'declared predecessor is an external run reference', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  replaceOnce(
    join(path, 'run-manifest.md'),
    '- predecessor_run: none',
    '- predecessor_run: RUN-prior-fixture',
  );
  requirePass(runFixture(root, relativePath), ['K2.2', 'K2.5']);
});

addCase('K2', 'RFC 3339 fractional timestamps remain ordered', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  replaceOnce(
    join(path, 'run-manifest.md'),
    '| 1 | DRAFT | 2026-07-16 08:00 UTC |',
    '| 1 | DRAFT | 2026-07-16T08:00:00.123Z |',
  );
  replaceOnce(
    join(path, 'run-manifest.md'),
    '| 2 | CORPUS-FROZEN | 2026-07-16 08:20 UTC |',
    '| 2 | CORPUS-FROZEN | 2026-07-16T08:00:00.456Z |',
  );
  replaceOnce(
    join(path, 'ledgers', 'extraction-criteria.md'),
    '- written: 2026-07-16 08:25 UTC',
    '- written: 2026-07-16T08:25:00.123456789Z',
  );
  replaceOnce(
    join(path, 'run-log.md'),
    '## 2026-07-16 08:40 UTC — S2 — entry',
    '## 2026-07-16T08:40:00.456Z — S2 — entry',
  );
  requirePass(runFixture(root, relativePath), ['K2.2', 'K2.9']);
  replaceOnce(
    join(path, 'run-manifest.md'),
    '| 1 | DRAFT | 2026-07-16T08:00:00.123Z |',
    '| 1 | DRAFT | 2026-07-16T08:00:00.789Z |',
  );
  requireFailure(runFixture(root, relativePath), 'K2.2');
});

addCase('K2', 'predecessor id cited outside manifest is dangling', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  replaceOnce(
    join(path, 'run-manifest.md'),
    '- predecessor_run: none',
    '- predecessor_run: RUN-prior-fixture',
  );
  appendFileSync(
    join(path, 'run-log.md'),
    '\nUnresolved cross-run citation: RUN-prior-fixture.\n',
  );
  requireFailure(runFixture(root, relativePath), 'K2.5');
});

addCase('K2', 'fixture forbidden token and real-run exemption', (root) => {
  const fixtureRelative = join('docs', 'fixtures', 'run-slice-2');
  const fixturePath = copyFixture('run-slice-2', root, fixtureRelative);
  appendFileSync(join(fixturePath, 'run-log.md'), '\nFixture-only token: Phase\n');
  requireFailure(runFixture(root, fixtureRelative), 'K2.3');

  const deferredNameFixtureRelative =
    join('docs', 'fixtures', 'run-slice-2-deferred-consumer-name');
  const deferredNameFixturePath =
    copyFixture('run-slice-2', root, deferredNameFixtureRelative);
  const deferredBusinessIntelligenceConsumerName = ['sense', 'net'].join('');
  appendFileSync(
    join(deferredNameFixturePath, 'run-log.md'),
    `\nFixture-only deferred-consumer name: ${deferredBusinessIntelligenceConsumerName}\n`,
  );
  const deferredNameForbiddenResult = runFixture(root, deferredNameFixtureRelative);
  requireFailure(deferredNameForbiddenResult, 'K2.3');
  requireOutputOmits(
    deferredNameForbiddenResult,
    deferredBusinessIntelligenceConsumerName,
  );

  const realRelative = join('runs', 'run-slice-2');
  const realPath = copyFixture('run-slice-2', root, realRelative);
  appendFileSync(
    join(realPath, 'run-log.md'),
    `\nCorpus-preserved tokens: Phase / ${deferredBusinessIntelligenceConsumerName}\n`,
  );
  const patterns = new Map([['K2.3', /real run is exempt/]]);
  const realRunResult = runFixture(root, realRelative);
  requirePass(realRunResult, ['K2.3'], patterns);
  requireOutputOmits(realRunResult, deferredBusinessIntelligenceConsumerName);
});

addFailureCase('K2', 'tampered source span', 'run-slice-2', 'K2.4', (path) => {
  replaceOnce(
    join(path, 'corpus', 'sources', 'SRC-101-access-model.md'),
    'built on token-gated membership',
    'built on token gated membership',
  );
});

addFailureCase('K2', 'dangling packet id', 'run-slice-2', 'K2.5', (path) => {
  appendFileSync(
    join(path, 'clusters', 'route-cards', 'RC-01.md'),
    '\nUnresolved packet citation: PKT-9999.\n',
  );
});

addFailureCase('K2', 'dangling run id', 'run-slice-2', 'K2.5', (path) => {
  appendFileSync(join(path, 'run-log.md'), '\nCross-run citation: RUN-not-present.\n');
});

addFailureCase('K2', 'dangling negative-boundary id', 'run-slice-2', 'K2.5', (path) => {
  appendFileSync(
    join(path, 'projections', 'traces', 'product-doctrine-trace.md'),
    '\nDangling boundary citation: NB-999.\n',
  );
});

addCase('K2', 'dangling projection id', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  replaceOnce(
    join(path, 'projections', 'traces', 'product-doctrine-trace.md'),
    '- projection_id: PRJ-001',
    '- projection_id: PRJ-999',
  );
  const report = requireFailure(runFixture(root, relativePath), 'K2.5');
  requireCheck(report, 'K6.1', 'FAIL');
});

addCase('K2', 'duplicate projection id definition', (root) => {
  const relativePath = join('docs', 'fixtures', 'run-slice-2');
  const path = copyFixture('run-slice-2', root, relativePath);
  replaceOnce(
    join(path, 'projections', 'commission-prd.md'),
    '| projection_id | PRJ-002 |',
    '| projection_id | PRJ-001 |',
  );
  const report = requireFailure(runFixture(root, relativePath), 'K2.5');
  requireCheck(report, 'K6.1', 'FAIL');
});

addFailureCase('K2', 'claim carries two dispositions', 'run-slice-2', 'K2.6', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'claim-inventory.md'),
    '| design-intent | carried | Directly stated and inside the declared access-model scope.',
    '| design-intent | carried, deferred | Directly stated and inside the declared access-model scope.',
  );
});

addFailureCase('K2', 'disposition ledger total off by one', 'run-slice-2', 'K2.7', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'disposition-ledger.md'),
    '| **total** | **14** |',
    '| **total** | **15** |',
  );
});

addFailureCase('K2', 'canonical merge drops absorbed source', 'run-slice-2', 'K2.8', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'claim-inventory.md'),
    '| PKT-0002, PKT-0007, PKT-0012 | SRC-101, SRC-102, SRC-104 | factual | merged |',
    '| PKT-0002, PKT-0007, PKT-0012 | SRC-101, SRC-102 | factual | merged |',
  );
});

addFailureCase('K2', 'criteria written after S2 entry', 'run-slice-2', 'K2.9', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'extraction-criteria.md'),
    '- written: 2026-07-16 08:25 UTC',
    '- written: 2026-07-16 08:45 UTC',
  );
});

addFailureCase('K2', 'dangling supersession status', 'run-slice-2', 'K2.10', (path) => {
  replaceRegexOnce(
    join(path, 'ledgers', 'packet-index.md'),
    /(\| PKT-0014 [^\n]*\| )active( \|)/,
    '$1superseded-by:PKT-0999$2',
  );
});

addFailureCase('K2', 'Precis section 4 omits an active claim', 'run-slice-2', 'K2.11', (path) => {
  removeLine(join(path, 'precis.md'), /^\| CC-114 \|/);
});

// K3: the K3.4 and K3.6 cases mutate the two seeded issue-18 patterns.
addFailureCase('K3', 'unknown evidence role', 'evidence-role-adversarial', 'K3.1', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'evidence-roles.md'),
    '| CC-201 | SRC-202 | corroborative |',
    '| CC-201 | SRC-202 | supportive |',
  );
});

addFailureCase('K3', 'edge points to inactive claim', 'evidence-role-adversarial', 'K3.2', (path) => {
  replaceRegexOnce(
    join(path, 'ledgers', 'claim-inventory.md'),
    /(\| CC-203 [^\n]*\| )active( \|)/,
    '$1retracted:fixture mutation$2',
  );
});

addFailureCase('K3', 'load-bearing edge lacks removal effect', 'evidence-role-adversarial', 'K3.3', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'evidence-roles.md'),
    '| CC-201 | SRC-201 | load-bearing | verified-primary | confidence-decreases |',
    '| CC-201 | SRC-201 | load-bearing | verified-primary | |',
  );
});

addFailureCase('K3', 'seeded decorative-only carried claim', 'evidence-role-adversarial', 'K3.4', (path) => {
  const ledger = join(path, 'ledgers', 'evidence-roles.md');
  replaceOnce(
    ledger,
    '| CC-201 | SRC-201 | load-bearing | verified-primary | confidence-decreases |',
    '| CC-201 | SRC-201 | decorative | verified-primary | |',
  );
  replaceOnce(
    ledger,
    '| CC-201 | SRC-202 | corroborative |',
    '| CC-201 | SRC-202 | decorative |',
  );
});

addFailureCase('K3', 'coverage accounting counts decorative support', 'evidence-role-adversarial', 'K3.5', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'evidence-roles.md'),
    '| CC-205 | SRC-206 | load-bearing | verified-primary | confidence-decreases |',
    '| CC-205 | SRC-206 | decorative | verified-primary | |',
  );
});

addFailureCase('K3', 'seeded synthetic source cannot confirm', 'evidence-role-adversarial', 'K3.6', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'claim-inventory.md'),
    '| factual | unresolved | only source is unattributed and unverifiable |',
    '| factual | carried | only source is unattributed and unverifiable |',
  );
});

addFailureCase('K3', 'merge drops absorbed contradiction', 'evidence-role-adversarial', 'K3.7', (path) => {
  removeLine(
    join(path, 'ledgers', 'evidence-roles.md'),
    /^\| CC-204 \| SRC-205 \| contradictory \|/,
  );
});

addFailureCase('K3', 'inference marker has dangling basis', 'evidence-role-adversarial', 'K3.8', (path) => {
  replaceOnce(
    join(path, 'ledgers', 'evidence-roles.md'),
    '|----------|------------------------------------|------------------|\n',
    '|----------|------------------------------------|------------------|\n'
      + '| CC-201 | CC-999 | basis deliberately absent in mutation | \n',
  );
});

// K4/K5: exact minimum from the route-card and taint-gate checker spec.
addFailureCase('K4/K5', 'route card lists zero packets', 'run-slice-2', 'K4.2', (path) => {
  replaceOnce(
    join(path, 'clusters', 'route-cards', 'RC-04.md'),
    '| Packet/source IDs | PKT-0008; SRC-102 |',
    '| Packet/source IDs | SRC-102 |',
  );
});

addFailureCase('K4/K5', 'route card cites missing packet', 'run-slice-2', 'K4.2', (path) => {
  replaceOnce(
    join(path, 'clusters', 'route-cards', 'RC-04.md'),
    'PKT-0008; SRC-102',
    'PKT-9999; SRC-102',
  );
});

addFailureCase('K4/K5', 'pending posture has no referent', 'run-slice-2', 'K4.3', (path) => {
  replaceOnce(
    join(path, 'clusters', 'route-cards', 'RC-04.md'),
    '| Unresolved external referents | REF-01 |',
    '| Unresolved external referents | none |',
  );
  replaceOnce(
    join(path, 'ledgers', 'external-referents.md'),
    '| RC-04, CC-108 | unresolved |',
    '| none | unresolved |',
  );
});

addFailureCase('K4/K5', 'resolved referent lacks later reroute', 'run-slice-2', 'K4.3', (path) => {
  const card = join(path, 'clusters', 'route-cards', 'RC-03.md');
  replaceRegexOnce(
    card,
    /^\| Posture history \|.*\|$/m,
    '| Posture history | 2026-07-16: unrouted-pending-external-referent - awaiting REF-02 |',
  );
  replaceOnce(
    card,
    '| Unresolved external referents | none |',
    '| Unresolved external referents | REF-02 |',
  );
});

addFailureCase('K4/K5', 'pre-cluster materialized as a document', 'run-slice-2', 'K4.4', (path) => {
  writeFileSync(
    join(path, 'clusters', 'PC-2.md'),
    '# Materialized Pre-Cluster PC-2\n',
  );
});

addFailureCase('K4/K5', 'dependency cycle lacks mutual annotation', 'run-slice-2', 'K4.5', (path) => {
  replaceOnce(
    join(path, 'clusters', 'route-cards', 'RC-01.md'),
    '| Depends on | none |',
    '| Depends on | RC-02 |',
  );
});

addFailureCase('K4/K5', 'tainted synthesis claims external completeness', 'run-slice-2', 'K5.2', (path) => {
  const synthesis = join(path, 'synthesis', 'cluster-synthesis.md');
  replaceOnce(
    synthesis,
    'external-referent unresolved',
    'unresolved against an external referent',
  );
  appendFileSync(
    synthesis,
    '\n\nRC-02 and CC-104 are externally complete.\n',
  );
});

addFailureCase('K4/K5', 'Precis section 17 hides load-bearing taint', 'run-slice-2', 'K5.3', (path) => {
  replaceRegexOnce(
    join(path, 'precis.md'),
    /external-referent unresolved/i,
    'unresolved against an external referent',
  );
});

addFailureCase('K4/K5', 'supplied referent has no supplier or intake', 'run-slice-2', 'K5.4', (path) => {
  replaceRegexOnce(
    join(path, 'ledgers', 'external-referents.md'),
    /(\| REF-02 [^\n]*\| supplied \|)[^|]*\|[^|]*\|/,
    '$1 | |',
  );
});

// K6: the required K6.1-K6.8 defects, boundary-backing resolution, and the
// registered type contract. The clean baseline separately guards K6.9,
// honest gaps, and the surfaced-open happy path.
addFailureCase('K6', 'commission hash mismatch', 'projection-adversarial', 'K6.1', (path) => {
  const commission = join(path, 'projections', 'commission-product-doctrine.md');
  const text = readFileSync(commission, 'utf8');
  const match = text.match(
    /(\| precis hash at commissioning \| sha256:)([a-f0-9])([a-f0-9]{63})( \|)/,
  );
  if (!match) throw new Error(`${commission} does not contain a commissioned Précis hash`);
  replaceOnce(
    commission,
    match[0],
    `${match[1]}${match[2] === '0' ? '1' : '0'}${match[3]}${match[4]}`,
  );
});

addFailureCase('K6', 'commission repeats projection id row', 'projection-adversarial', 'K6.1', (path) => {
  replaceOnce(
    join(path, 'projections', 'commission-product-doctrine.md'),
    '| projection_id | PRJ-201 |',
    '| projection_id | PRJ-201 |\n| projection_id | PRJ-201 |',
  );
});

addFailureCase('K6', 'carried claim missing from selection', 'projection-adversarial', 'K6.2', (path) => {
  removeLine(
    join(path, 'projections', 'traces', 'product-doctrine-selection.md'),
    /^\| CC-201 \|/,
  );
});

addFailureCase('K6', 'trace backs onto retracted claim', 'projection-adversarial', 'K6.3', (path) => {
  replaceRegexOnce(
    join(path, 'ledgers', 'claim-inventory.md'),
    /(\| CC-201 [^\n]*\| )active( \|)/,
    '$1retracted:fixture mutation$2',
  );
});

addFailureCase('K6', 'boundary trace backs onto missing boundary', 'projection-adversarial', 'K6.3', (path) => {
  replaceRegexOnce(
    join(path, 'projections', 'traces', 'product-doctrine-trace.md'),
    /(\| [^|\n]+ \| boundary \| )NB-\d+/,
    '$1NB-999',
  );
});

addFailureCase('K6', 'rendered paragraph is untraced', 'projection-adversarial', 'K6.4', (path) => {
  appendFileSync(
    join(path, 'projections', 'tier-1', 'product-doctrine.md'),
    '\nA newly added statement has no projection-trace row.\n',
  );
});

addFailureCase('K6', 'load-bearing trace has empty backing', 'projection-adversarial', 'K6.5', (path) => {
  replaceOnce(
    join(path, 'projections', 'traces', 'product-doctrine-trace.md'),
    '| §2 ¶1 | load-bearing | CC-201 |',
    '| §2 ¶1 | load-bearing | |',
  );
});

addFailureCase('K6', 'trace backs onto do-not-use claim', 'projection-adversarial', 'K6.6', (path) => {
  replaceOnce(
    join(path, 'projections', 'traces', 'product-doctrine-trace.md'),
    '| §2 ¶1 | load-bearing | CC-201 |',
    '| §2 ¶1 | load-bearing | CC-208 |',
  );
});

addFailureCase('K6', 'open item is anchored outside declared section', 'projection-adversarial', 'K6.7', (path) => {
  replaceOnce(
    join(path, 'projections', 'traces', 'product-doctrine-selection.md'),
    '| CC-204 | deferred | surfaced-as-open | §6 Open Questions and Tensions |',
    '| CC-204 | deferred | surfaced-as-open | §5 Open Questions and Tensions |',
  );
});

addFailureCase('K6', 'tainted projection lacks prominent marker', 'projection-adversarial', 'K6.8', (path) => {
  replaceOnce(
    join(path, 'projections', 'tier-1', 'product-doctrine.md'),
    'external-referent unresolved',
    'unresolved against an external referent',
  );
});

addFailureCase('K6', 'registered type is missing a required section', 'projection-adversarial', 'K6.10', (path) => {
  replaceOnce(
    join(path, 'projections', 'tier-1', 'product-doctrine.md'),
    '## 8. Change Conditions',
    '## 9. Change Conditions',
  );
});

function verifyDeclaredCounts(): void {
  for (const [group, expected] of EXPECTED_CASES) {
    const actual = cases.filter((test) => test.group === group).length;
    if (actual !== expected) {
      throw new Error(`${group} declares ${actual} cases, expected exactly ${expected}`);
    }
  }
  const unknown = [...new Set(cases.map((test) => test.group))]
    .filter((group) => !EXPECTED_CASES.has(group));
  if (unknown.length) throw new Error(`unknown case groups: ${unknown.join(', ')}`);
}

try {
  verifyDeclaredCounts();

  runBaseline(
    'golden run',
    'run-slice-2',
    ['K2.1', 'K2.12', 'K3.1', 'K3.8', 'K4.1', 'K4.6', 'K5.1', 'K5.4', 'K6.10'],
  );
  runBaseline(
    'evidence roles',
    'evidence-role-adversarial',
    ['K3.1', 'K3.2', 'K3.3', 'K3.4', 'K3.5', 'K3.6', 'K3.7', 'K3.8'],
  );
  runBaseline(
    'projection',
    'projection-adversarial',
    ['K6.1', 'K6.2', 'K6.3', 'K6.4', 'K6.5', 'K6.6', 'K6.7', 'K6.8', 'K6.9', 'K6.10'],
  );

  for (const test of cases) {
    const root = sandbox(`${test.group}-${test.name}`);
    try {
      test.execute(root);
      caseResults.push({ group: test.group, name: test.name, status: 'PASS' });
      if (!options.json) console.log(`PASS ${test.group} ${test.name}`);
    } catch (error) {
      const message = errorMessage(error);
      caseResults.push({
        group: test.group,
        name: test.name,
        status: 'FAIL',
        error: message,
      });
      if (!options.json) console.log(`FAIL ${test.group} ${test.name}: ${message}`);
    }
  }
} catch (error) {
  caseResults.push({
    group: 'harness',
    name: 'setup',
    status: 'FAIL',
    error: errorMessage(error),
  });
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}

const failedBaselines = baselineResults.filter((record) => record.status === 'FAIL');
const failedCases = caseResults.filter((record) => record.status === 'FAIL');
const passedCases = caseResults.filter((record) => record.status === 'PASS').length;
const expectedTotal = [...EXPECTED_CASES.values()].reduce((sum, value) => sum + value, 0);
const result = failedBaselines.length === 0
  && failedCases.length === 0
  && passedCases === expectedTotal
  ? 'PASS'
  : 'FAIL';

if (options.json) {
  console.log(JSON.stringify({
    result,
    expectedCases: expectedTotal,
    passedCases,
    baselines: baselineResults,
    cases: caseResults,
  }, null, 2));
} else if (result === 'PASS') {
  console.log('');
  console.log(
    `RESULT: PASS (${passedCases}/${expectedTotal} conformance cases; `
      + `${baselineResults.length}/${baselineResults.length} clean baselines)`,
  );
} else {
  console.log('');
  console.log(
    `RESULT: FAIL (${passedCases}/${expectedTotal} conformance cases; `
      + `${baselineResults.length - failedBaselines.length}/${baselineResults.length} clean baselines)`,
  );
}

process.exitCode = result === 'PASS' ? 0 : 1;
