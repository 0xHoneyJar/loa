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
import {
  mdLineSpan,
  sha256,
} from './lib/check-helpers.ts';
import { sourceWalkReviewBasisDigest } from './lib/checks-k2.ts';
import {
  EXACT_EVIDENCE_FORMAT,
  loadRun,
} from './lib/run-model.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const FIXTURES = join(REPO_ROOT, 'docs', 'fixtures');
const PRECIS_CHECKER = join(REPO_ROOT, 'scripts', 'validate-precis-fixtures.ts');
const RUN_CHECKER = join(REPO_ROOT, 'scripts', 'validate-run.ts');
const EXPECTED_CASES = new Map<string, number>([
  ['K1', 5],
  ['K2', 22],
  ['K2E', 21],
  ['K2S2', 41],
  ['K3', 8],
  ['K4/K5', 9],
  ['K6', 11],
]);

const options = {
  json: false,
  help: false,
  error: '',
  group: '',
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
const argv = process.argv.slice(2);
for (let index = 0; index < argv.length; index++) {
  const arg = argv[index];
  if (arg === '--json') options.json = true;
  else if (arg === '--help' || arg === '-h') options.help = true;
  else if (arg === '--group') options.group = argv[++index] || '';
  else if (arg.startsWith('--group=')) options.group = arg.slice('--group='.length);
  else options.error = `unknown argument "${arg}"`;
}

if (options.help) {
  console.log('Usage: node scripts/test-conformance-mutations.ts [--group GROUP] [--json]');
  process.exit(0);
}
if (options.error) {
  console.error(options.error);
  process.exit(2);
}
if (options.group && !EXPECTED_CASES.has(options.group)) {
  console.error(`unknown mutation group "${options.group}"`);
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

function updateTableRow(
  path: string,
  firstCell: string,
  update: (cells: string[]) => void,
): void {
  const text = readFileSync(path, 'utf8');
  const lines = text.split('\n');
  const index = lines.findIndex((line) => line.startsWith(`| ${firstCell} |`));
  if (index < 0) throw new Error(`${path} has no table row for ${firstCell}`);
  const cells = lines[index].split('|').slice(1, -1).map((cell) => cell.trim());
  update(cells);
  lines[index] = `| ${cells.join(' | ')} |`;
  writeFileSync(path, lines.join('\n'));
}

function framedExactEvidenceHash(fragments: readonly Buffer[]): string {
  const parts: Buffer[] = [Buffer.from(`${EXACT_EVIDENCE_FORMAT}\0`, 'utf8')];
  for (const fragment of fragments) {
    const length = Buffer.alloc(8);
    length.writeBigUInt64BE(BigInt(fragment.byteLength));
    parts.push(length, fragment);
  }
  return sha256(Buffer.concat(parts));
}

function removeSourceWalkExit(path: string): void {
  replaceOnce(
    join(path, 'run-log.md'),
    '## 2026-08-14 08:45 UTC — S2 — exit\n\n'
      + 'Closed structural traversal and resume accounting for SRC-401. This does not\n'
      + 'claim perfect recall or semantic review correctness.',
    '## 2026-08-14 08:45 UTC — S2 — blocked checkpoint\n\n'
      + 'Recorded the current structurally blocked state for SRC-401. No S2 exit is\n'
      + 'claimed.',
  );
}

function makeTrueOpenGapState(
  path: string,
  completionState: 'complete' | 'blocked',
): void {
  removeLine(join(path, 'ledgers', 'source-walk.md'), /^\| EVT-0405 \|/);
  removeLine(join(path, 'ledgers', 'packet-index.md'), /^\| PKT-0405 \|/);
  removeLine(join(path, 'ledgers', 'packet-index.md'), /^\| EVID-0404 \|/);
  removeLine(join(path, 'ledgers', 'packet-index.md'), /^\| FRAG-0405 \|/);
  removeLine(join(path, 'ledgers', 'packet-index.md'), /^\| XFORM-0404 \|/);
  updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'GAP-0401', (cells) => {
    cells[9] = 'none';
    cells[10] = 'none';
    cells[11] = 'open';
    cells[12] = 'fresh reviewer found one synthetic omission; canonical reconciliation is pending';
  });
  updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'SRC-401', (cells) => {
    cells[5] = completionState;
    cells[7] = completionState === 'blocked'
      ? 'primary walk ended but GAP-0401 remains structurally open'
      : 'invalid mutation attempts completion while GAP-0401 remains open';
  });
  removeSourceWalkExit(path);
}

function refreshReviewBasisDigest(path: string, cursorId = 'CUR-0406'): void {
  const digest = sourceWalkReviewBasisDigest(loadRun(path), 'SRC-401', cursorId);
  if (!digest) throw new Error(`could not recompute review basis at ${cursorId}`);
  updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'GAP-0401', (cells) => {
    cells[4] = cursorId;
    cells[5] = digest;
  });
}

function makeSamePositionGapReconciliation(
  path: string,
  eventOrdinal = '2',
): void {
  const reviewBasisBefore = sourceWalkReviewBasisDigest(
    loadRun(path),
    'SRC-401',
    'CUR-0406',
  );
  if (!reviewBasisBefore) throw new Error('could not compute the original review basis');

  const span = mdLineSpan(
    join(path, 'corpus', 'sources', 'SRC-401-source-walk.txt'),
    5,
    5,
  );
  if (
    !span?.bytes
    || span.startByte === null
    || span.endByte === null
  ) {
    throw new Error('source-walk fixture line 5 is not reopenable');
  }
  const fragmentHash = `sha256:${sha256(span.bytes)}`;
  const evidenceHash = `sha256:${framedExactEvidenceHash([span.bytes])}`;
  const rendered = span.bytes.toString('utf8').replace(/\n$/, '');
  const renderedHash = `sha256:${sha256(Buffer.from(rendered, 'utf8'))}`;
  const packetIndex = join(path, 'ledgers', 'packet-index.md');
  const sourceWalk = join(path, 'ledgers', 'source-walk.md');

  updateTableRow(packetIndex, 'PKT-0405', (cells) => {
    cells[2] = 'L5-L5';
    cells[3] = fragmentHash;
    cells[4] = rendered;
  });
  updateTableRow(packetIndex, 'EVID-0404', (cells) => {
    cells[5] = evidenceHash;
  });
  updateTableRow(packetIndex, 'FRAG-0405', (cells) => {
    cells[5] = 'L5-L5';
    cells[8] = fragmentHash;
    cells[9] = span.bytes!.toString('base64');
  });
  updateTableRow(packetIndex, 'XFORM-0404', (cells) => {
    cells[3] = evidenceHash;
    cells[4] = evidenceHash;
    cells[5] = rendered;
    cells[6] = renderedHash;
  });
  updateTableRow(sourceWalk, 'EVT-0405', (cells) => {
    cells[2] = String(span.startByte);
    cells[3] = String(span.endByte);
    cells[4] = 'SP-0402';
    cells[5] = eventOrdinal;
  });
  updateTableRow(sourceWalk, 'GAP-0401', (cells) => {
    cells[7] = String(span.startByte);
    cells[8] = String(span.endByte);
    cells[12] = 'fresh reviewer found a same-position candidate after the terminal primary review basis';
  });

  const updatedModel = loadRun(path);
  const reviewBasisAfter = sourceWalkReviewBasisDigest(
    updatedModel,
    'SRC-401',
    'CUR-0406',
  );
  const recordedBasis = updatedModel.sourceWalk.gapReviews.find(
    (row) => row.values.gapReviewId === 'GAP-0401',
  )?.values.reviewBasisDigest;
  if (
    reviewBasisAfter !== reviewBasisBefore
    || recordedBasis !== reviewBasisAfter
  ) {
    throw new Error('gap reconciliation changed the recorded primary review basis');
  }
}

function replaceEncodedUtf8(path: string, before: string, after: string): void {
  replaceOnce(
    path,
    Buffer.from(before, 'utf8').toString('base64'),
    Buffer.from(after, 'utf8').toString('base64'),
  );
}

function swapAdjacentLines(
  path: string,
  firstPrefix: string,
  secondPrefix: string,
): void {
  const text = readFileSync(path, 'utf8');
  const lines = text.split('\n');
  const first = lines.findIndex((line) => line.startsWith(firstPrefix));
  const second = lines.findIndex((line) => line.startsWith(secondPrefix));
  if (first < 0 || second !== first + 1) {
    throw new Error(`${path} does not contain adjacent rows ${firstPrefix} / ${secondPrefix}`);
  }
  [lines[first], lines[second]] = [lines[second], lines[first]];
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
  messagePattern: RegExp | null = null,
): void {
  addCase(group, name, (root) => {
    const relativePath = join('docs', 'fixtures', fixture);
    const fixturePath = copyFixture(fixture, root, relativePath);
    mutate(fixturePath, root);
    const report = requireFailure(runFixture(root, relativePath), expectedId);
    if (messagePattern) requireCheck(report, expectedId, 'FAIL', messagePattern);
  });
}

function runBaseline(
  name: string,
  fixture: string,
  ids: readonly string[],
  messagePatterns: ReadonlyMap<string, RegExp> = new Map(),
  prepare: FixtureMutation | null = null,
): void {
  const root = sandbox(`baseline-${name}`);
  const relativePath = join('docs', 'fixtures', fixture);
  try {
    const fixturePath = copyFixture(fixture, root, relativePath);
    prepare?.(fixturePath, root);
    requirePass(runFixture(root, relativePath), ids, messagePatterns);
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

// K2E: adopted calibration Slice 1 exact-byte and ordered-fragment failures.
addFailureCase(
  'K2E',
  'curly-quote drift',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceEncodedUtf8(
      join(path, 'ledgers', 'packet-index.md'),
      'The console recorded “exact” status for the ﬂow.\n',
      'The console recorded "exact" status for the ﬂow.\n',
    );
  },
  /FRAG-0301 exact bytes differ from frozen source/,
);

addFailureCase(
  'K2E',
  'ligature drift',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceEncodedUtf8(
      join(path, 'ledgers', 'packet-index.md'),
      'The console recorded “exact” status for the ﬂow.\n',
      'The console recorded “exact” status for the flow.\n',
    );
  },
  /FRAG-0301 exact bytes differ from frozen source/,
);

addFailureCase(
  'K2E',
  'newline-byte change',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceEncodedUtf8(
      join(path, 'ledgers', 'packet-index.md'),
      'The console recorded “exact” status for the ﬂow.\n',
      'The console recorded “exact” status for the ﬂow.\r\n',
    );
  },
  /FRAG-0301 exact bytes differ from frozen source/,
);

addFailureCase(
  'K2E',
  'fragment order swap',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    swapAdjacentLines(
      join(path, 'ledgers', 'packet-index.md'),
      '| FRAG-0304 |',
      '| FRAG-0305 |',
    );
  },
  /EVID-0303 fragment rows must appear in explicit fragment_order/,
);

addFailureCase(
  'K2E',
  'undeclared fragment join',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0303 | PKT-0304, PKT-0305 | exact | 2 | separate-fragments |',
      '| EVID-0303 | PKT-0304, PKT-0305 | exact | 2 | |',
    );
  },
  /EVID-0303 join_policy "\(blank\)" is undeclared/,
);

addFailureCase(
  'K2E',
  'normalized text substitutes for exact evidence',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| FRAG-0301 | EVID-0301 | PKT-0301 | 1 | SRC-301 | L3-L3 | frozen-source | exact-source-bytes |',
      '| FRAG-0301 | EVID-0301 | PKT-0301 | 1 | SRC-301 | L3-L3 | frozen-source | normalized-text |',
    );
  },
  /FRAG-0301 byte_role "normalized-text" cannot substitute/,
);

addFailureCase(
  'K2E',
  'missing frozen source bytes',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    rmSync(join(path, 'corpus', 'sources', 'SRC-301-exact-evidence.md'));
  },
  /FRAG-0301 frozen source locus .* is not a readable file/,
);

addFailureCase(
  'K2E',
  'changed fragment hash',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| exact-source-bytes | sha256:725fc130d2473090f51c7456b74d34683b57793729f80ccea7b56aeb92931cfe | QWRqYWNlbnQgZnJhZ21lbnQgb25lLgo= |',
      '| exact-source-bytes | sha256:025fc130d2473090f51c7456b74d34683b57793729f80ccea7b56aeb92931cfe | QWRqYWNlbnQgZnJhZ21lbnQgb25lLgo= |',
    );
  },
  /FRAG-0302 fragment_hash does not match exact source bytes/,
);

addFailureCase(
  'K2E',
  'invalid exact-fragment locator bounds',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| FRAG-0304 | EVID-0303 | PKT-0304 | 1 | SRC-301 | L5-L5 |',
      '| FRAG-0304 | EVID-0303 | PKT-0304 | 1 | SRC-301 | L99-L99 |',
    );
  },
  /FRAG-0304 locator L99-L99 is outside SRC-301/,
);

addFailureCase(
  'K2E',
  'normalization changes exact evidence identity',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| XFORM-0302 | EVID-0301 | normalized | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b |',
      '| XFORM-0302 | EVID-0301 | normalized | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b | sha256:1ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b |',
    );
  },
  /XFORM-0302 changes exact evidence identity during normalized/,
);

addFailureCase(
  'K2E',
  'current run omits exact-evidence activation marker',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    removeLine(
      join(path, 'ledgers', 'packet-index.md'),
      /^- exact_evidence_format: aleph-exact-evidence\/v1$/,
    );
  },
  /run format 1\.1\.0-provisional requires exact_evidence_format aleph-exact-evidence\/v1/,
);

addCase('K2E', 'current run requires complete forward execution identity', (root) => {
  const requiredFields = [
    'core_id',
    'core_version',
    'core_digest',
    'adapter_id',
    'adapter_version',
    'adapter_digest',
    'bundle_id',
    'bundle_digest',
    'bundle_lock_ref',
    'checker_digest',
    'adapter_protocol_version',
    'host_identity',
    'runtime_snapshot_ref',
    'runtime_snapshot_digest',
  ];
  for (const field of requiredFields) {
    const relativePath = join(
      'docs',
      'fixtures',
      `exact-evidence-missing-${field.replaceAll('_', '-')}`,
    );
    const path = copyFixture('exact-evidence-fragments', root, relativePath);
    removeLine(
      join(path, 'run-manifest.md'),
      new RegExp(`^- ${field}:`),
    );
    const report = requireFailure(runFixture(root, relativePath), 'K2.2');
    requireCheck(
      report,
      'K2.2',
      'FAIL',
      new RegExp(`${field} must be defined exactly once`),
    );
  }

  const profileRows = [
    ['model_ids', /^\| model_ids \(per role, exact strings; or "human"\) \|/],
    ['adapter profile ID + digest', /^\| adapter profile ID \+ digest \|/],
    ['model/context/effort mapping actually used', /^\| model\/context\/effort mapping actually used \|/],
  ] as const;
  for (const [field, pattern] of profileRows) {
    const relativePath = join(
      'docs',
      'fixtures',
      `exact-evidence-missing-${field.replaceAll(/[^A-Za-z0-9]+/g, '-').toLowerCase()}`,
    );
    const path = copyFixture('exact-evidence-fragments', root, relativePath);
    removeLine(join(path, 'run-manifest.md'), pattern);
    const report = requireFailure(runFixture(root, relativePath), 'K2.2');
    requireCheck(
      report,
      'K2.2',
      'FAIL',
      new RegExp(`${field.replace(/[+/]/g, '\\$&')} must be defined exactly once`),
    );
  }
});

addCase('K2E', 'S2 evidence cannot be hidden by suppressing DISTILLING', (root) => {
  const relativePath = join('docs', 'fixtures', 'exact-evidence-state-suppressed');
  const path = copyFixture('exact-evidence-fragments', root, relativePath);
  removeLine(
    join(path, 'run-manifest.md'),
    /^\| 3 \| DISTILLING \| 2026-08-13 09:20 UTC \|/,
  );
  removeLine(
    join(path, 'ledgers', 'packet-index.md'),
    /^- exact_evidence_format: aleph-exact-evidence\/v1$/,
  );
  replaceRegexOnce(
    join(path, 'ledgers', 'packet-index.md'),
    /\n## Exact evidence records[\s\S]*?\n## Per-source completion\n/u,
    '\n## Per-source completion\n',
  );
  const report = requireFailure(runFixture(root, relativePath), 'K2.2');
  requireCheck(
    report,
    'K2.2',
    'FAIL',
    /state log understates DISTILLING/,
  );
  requireCheck(
    report,
    'K2.13',
    'FAIL',
    /run format 1\.1\.0-provisional requires exact_evidence_format aleph-exact-evidence\/v1/,
  );
});

addFailureCase(
  'K2E',
  'degraded evidence missing source binding',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | none | L10-L10 |',
    );
  },
  /EVID-0304 degraded evidence requires a degraded_source_id/,
);

addFailureCase(
  'K2E',
  'degraded evidence references nonexistent source',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-999 | L10-L10 |',
    );
  },
  /EVID-0304 degraded source SRC-999 does not resolve/,
);

addFailureCase(
  'K2E',
  'degraded evidence has invalid source locator',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L0-L0 |',
    );
  },
  /EVID-0304 degraded locator "L0-L0" is not L<start>-L<end>/,
);

addFailureCase(
  'K2E',
  'degraded md-lines locator is outside the frozen source',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L999-L999 |',
    );
  },
  /EVID-0304 degraded locator L999-L999 is outside SRC-301/,
);

addFailureCase(
  'K2E',
  'degraded source locus is not readable',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'corpus', 'manifest.md'),
      '| SRC-301 | design-note | sources/SRC-301-exact-evidence.md | md-lines | sha256:f53ee9454205a5ca11c300add045a2cccf2748063383b68c79029b65fa831e6c | 2026-08-13 | model-generated | none | synthetic bytes selected to exercise the exact-evidence format |',
      '| SRC-301 | design-note | sources/SRC-301-exact-evidence.md | md-lines | sha256:f53ee9454205a5ca11c300add045a2cccf2748063383b68c79029b65fa831e6c | 2026-08-13 | model-generated | none | synthetic bytes selected to exercise the exact-evidence format |\n'
        + '| SRC-302 | design-note | sources/SRC-302-missing.md | md-lines | sha256:f53ee9454205a5ca11c300add045a2cccf2748063383b68c79029b65fa831e6c | 2026-08-13 | model-generated | none | missing degraded source fixture |',
    );
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-301 | L10-L10 |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none | SRC-302 | L10-L10 |',
    );
  },
  /EVID-0304 degraded source SRC-302 locus "sources\/SRC-302-missing\.md" is not a readable file/,
);

addFailureCase(
  'K2E',
  'degraded evidence claims exact packet',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact |',
      '| EVID-0304 | PKT-0301 | degraded-non-exact |',
    );
  },
  /EVID-0304 degraded evidence must not claim packet_ids/,
);

addFailureCase(
  'K2E',
  'degraded evidence claims exact hash',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'packet-index.md'),
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | none |',
      '| EVID-0304 | none | degraded-non-exact | 0 | not-applicable | sha256:0ca32f456702bd71ce592fd5c3b29785fe1a3bf8c699bd558b2a1d9f472b0e2b |',
    );
  },
  /EVID-0304 degraded evidence must not claim an exact_evidence_hash/,
);

addFailureCase(
  'K2E',
  'degraded evidence claims exact fragment bytes',
  'exact-evidence-fragments',
  'K2.13',
  (path) => {
    const ledger = join(path, 'ledgers', 'packet-index.md');
    const text = readFileSync(ledger, 'utf8');
    const exactLine = text.split('\n').find((line) => line.startsWith('| FRAG-0301 |'));
    if (!exactLine) throw new Error('exact fixture has no FRAG-0301 row');
    const degradedLine = exactLine
      .replace('| FRAG-0301 | EVID-0301 |', '| FRAG-0399 | EVID-0304 |');
    writeFileSync(ledger, text.replace(exactLine, `${exactLine}\n${degradedLine}`));
  },
  /EVID-0304 degraded evidence must have zero exact fragments/,
);

// K2S2: adopted calibration Slice 2 source-walk and resume-accounting failures.
addFailureCase(
  'K2S2',
  'skipped source interval creates a structural hole',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    removeLine(join(path, 'ledgers', 'source-walk.md'), /^\| WLK-0406 \|/);
  },
  /SRC-401 walk has a hole before WLK-0407/,
);

addFailureCase(
  'K2S2',
  'first byte is uncovered',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0401 | SRC-401 | 0 | 17 |',
      '| WLK-0401 | SRC-401 | 1 | 17 |',
    );
  },
  /SRC-401 walk must begin at byte 0/,
);

addFailureCase(
  'K2S2',
  'terminal bytes are uncovered',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0409 | SRC-401 | 319 | 347 |',
      '| WLK-0409 | SRC-401 | 319 | 346 |',
    );
  },
  /SRC-401 complete walk ends at byte 346, expected 347/,
);

addFailureCase(
  'K2S2',
  'walk interval is reversed',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0402 | SRC-401 | 17 | 44 |',
      '| WLK-0402 | SRC-401 | 44 | 17 |',
    );
  },
  /WLK-0402 interval 44\.\.17 is reversed or empty/,
);

addFailureCase(
  'K2S2',
  'walk interval is out of bounds',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0409 | SRC-401 | 319 | 347 |',
      '| WLK-0409 | SRC-401 | 319 | 348 |',
    );
  },
  /WLK-0409 interval 319\.\.348 exceeds source length 347/,
);

addFailureCase(
  'K2S2',
  'walk intervals overlap without a shared-position event',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0402 | SRC-401 | 17 | 44 |',
      '| WLK-0402 | SRC-401 | 17 | 45 |',
    );
  },
  /SRC-401 walk overlaps before WLK-0403/,
);

addFailureCase(
  'K2S2',
  'shared-position ordinal is duplicated',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 |',
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 1 |',
    );
  },
  /SP-0401 event ordinals must be unique and contiguous/,
);

addFailureCase(
  'K2S2',
  'shared-position ordinal has a gap',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 |',
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 3 |',
    );
  },
  /SP-0401 event ordinals must be unique and contiguous/,
);

addFailureCase(
  'K2S2',
  'gap reconciliation shared-position ordinal has a gap',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    makeSamePositionGapReconciliation(path, '3');
  },
  /SP-0402 event ordinals must be unique and contiguous 1\.\.2/,
);

addFailureCase(
  'K2S2',
  'resume jumps beyond a same-position sibling',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0403 | SRC-401 | 44 | SP-0401 | 2 |',
      '| CUR-0403 | SRC-401 | 87 | SP-0401 | 2 |',
    );
  },
  /CUR-0403 shared-position cursor must remain at byte 44/,
);

addFailureCase(
  'K2S2',
  'recorded shared cursor cannot skip the next sibling',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'CUR-0403', (cells) => {
      cells[4] = '3';
    });
  },
  /CUR-0403 next_event_ordinal must identify a pending shared event in 2\.\.2/,
);

addFailureCase(
  'K2S2',
  'recorded shared cursor requires the immediately preceding event',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'CUR-0403', (cells) => {
      cells[6] = 'EVT-0402';
    });
  },
  /CUR-0403 predecessor event does not precede shared ordinal 2/,
);

addFailureCase(
  'K2S2',
  'resume cursor moves backwards',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0405 | SRC-401 | 268 | none |',
      '| CUR-0405 | SRC-401 | 43 | none |',
    );
  },
  /CUR-0405 cursor moves backwards from 87 to 43/,
);

addFailureCase(
  'K2S2',
  'resume cursor predecessor does not bind the next byte',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0405 | SRC-401 | 268 | none | none | WLK-0407 | EVT-0404 |',
      '| CUR-0405 | SRC-401 | 268 | none | none | WLK-0406 | EVT-0404 |',
    );
  },
  /CUR-0405 predecessor walk must end at next byte 268/,
);

addFailureCase(
  'K2S2',
  'resume cursor exceeds source end',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0405 | SRC-401 | 268 | none |',
      '| CUR-0405 | SRC-401 | 348 | none |',
    );
  },
  /CUR-0405 byte_offset 348 exceeds source length 347/,
);

addFailureCase(
  'K2S2',
  'admitted walk record references a nonexistent packet',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0403 | SRC-401 | 44 | 87 | admitted | PKT-0401, PKT-0402 |',
      '| WLK-0403 | SRC-401 | 44 | 87 | admitted | PKT-0999, PKT-0402 |',
    );
  },
  /WLK-0403 references missing packet PKT-0999/,
);

addFailureCase(
  'K2S2',
  'admitted packet lacks a Slice-1 exact evidence record',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    removeLine(join(path, 'ledgers', 'packet-index.md'), /^\| EVID-0401 \|/);
  },
  /PKT-0401 lacks a Slice-1 exact evidence record/,
);

addFailureCase(
  'K2S2',
  'excluded interval has no valid S1 criterion reference',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| excluded | none | exclusion:scaffolding |',
      '| excluded | none | exclusion:missing |',
    );
  },
  /WLK-0401 exclusion criterion "missing" does not resolve/,
);

addFailureCase(
  'K2S2',
  'deferred interval is open without reason or closure',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0404 | SRC-401 | 87 | 134 | deferred | none | none | INV-primary-0401 | resolved | candidate decision postponed for a second criteria pass | second criteria pass found no qualifying candidate |',
      '| WLK-0404 | SRC-401 | 87 | 134 | deferred | none | none | INV-primary-0401 | open | none | none |',
    );
  },
  /WLK-0404 deferred interval requires a nonempty reason/,
);

addFailureCase(
  'K2S2',
  'unsupported interval has no reason',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| WLK-0402 | SRC-401 | 17 | 44 | no-candidate-observed | none | none | INV-primary-0401 | closed | none | none |',
      '| WLK-0402 | SRC-401 | 17 | 44 | unsupported | none | none | INV-primary-0401 | open | none | none |',
    );
  },
  /WLK-0402 unsupported interval requires a nonempty reason/,
);

addFailureCase(
  'K2S2',
  'source is marked complete with an uncovered suffix',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    removeLine(join(path, 'ledgers', 'source-walk.md'), /^\| WLK-0409 \|/);
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0406 | SRC-401 | 347 | none | none | WLK-0409 | none |',
      '| CUR-0406 | SRC-401 | 319 | none | none | WLK-0408 | none |',
    );
  },
  /SRC-401 complete walk ends at byte 319, expected 347/,
);

addFailureCase(
  'K2S2',
  'source is marked complete with a pending shared-position event',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 | PKT-0402 | primary | INV-primary-0401 | committed |',
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 | PKT-0402 | primary | INV-primary-0401 | pending |',
    );
  },
  /SRC-401 complete source has pending event EVT-0402/,
);

addFailureCase(
  'K2S2',
  'complete source is missing a gap review',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    removeLine(join(path, 'ledgers', 'source-walk.md'), /^\| GAP-0401 \|/);
  },
  /SRC-401 complete source requires at least one gap review/,
);

addFailureCase(
  'K2S2',
  'gap reviewer reuses the primary producer invocation',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| GAP-0401 | SRC-401 | INV-primary-0401 | INV-gap-0402 |',
      '| GAP-0401 | SRC-401 | INV-primary-0401 | INV-primary-0401 |',
    );
  },
  /GAP-0401 reviewer invocation must differ from the primary producer/,
);

addFailureCase(
  'K2S2',
  'gap candidate remains unreconciled while completion is claimed',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| PKT-0405 | EVT-0405 | reconciled | fresh reviewer',
      '| PKT-0405 | EVT-0405 | open | fresh reviewer',
    );
  },
  /SRC-401 complete source has unreconciled gap review GAP-0401/,
);

addFailureCase(
  'K2S2',
  'cannot-determine gap review cannot close the source',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'GAP-0401', (cells) => {
      cells[6] = 'cannot-determine';
      cells[7] = 'none';
      cells[8] = 'none';
      cells[9] = 'none';
      cells[10] = 'none';
      cells[11] = 'blocked';
      cells[12] = 'source segment could not be judged';
    });
  },
  /SRC-401 complete source cannot use cannot-determine gap review GAP-0401/,
);

addFailureCase(
  'K2S2',
  'current source-walk marker is removed',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    removeLine(
      join(path, 'ledgers', 'source-walk.md'),
      /^- source_walk_format: aleph-source-walk\/v1$/,
    );
  },
  /run format 1\.2\.0-provisional requires source_walk_format aleph-source-walk\/v1/,
);

addCase('K2S2', 'current source-walk ledger is removed', (root) => {
  const relativePath = join('docs', 'fixtures', 'source-walk-accounting');
  const path = copyFixture('source-walk-accounting', root, relativePath);
  rmSync(join(path, 'ledgers', 'source-walk.md'));
  const report = requireFailure(runFixture(root, relativePath), 'K2.1');
  requireCheck(report, 'K2.14', 'FAIL', /requires ledgers\/source-walk\.md/);
});

addCase('K2S2', 'S2 walk evidence cannot be hidden by suppressing DISTILLING', (root) => {
  const relativePath = join('docs', 'fixtures', 'source-walk-accounting');
  const path = copyFixture('source-walk-accounting', root, relativePath);
  removeLine(
    join(path, 'run-manifest.md'),
    /^\| 3 \| DISTILLING \| 2026-08-14 08:20 UTC \|/,
  );
  const report = requireFailure(runFixture(root, relativePath), 'K2.2');
  requireCheck(report, 'K2.2', 'FAIL', /state log understates DISTILLING/);
});

addFailureCase(
  'K2S2',
  'cursor coordinate splits a UTF-8 code point',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'ledgers', 'source-walk.md'),
      '| CUR-0402 | SRC-401 | 44 | none |',
      '| CUR-0402 | SRC-401 | 30 | none |',
    );
  },
  /CUR-0402 byte_offset 30 splits a UTF-8 code point/,
);

addFailureCase(
  'K2S2',
  'frozen source bytes change after walk accounting',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    replaceOnce(
      join(path, 'corpus', 'sources', 'SRC-401-source-walk.txt'),
      'Ordinary café setup text.',
      'Ordinary cafe setup text.',
    );
  },
  /SRC-401 content_hash does not match the frozen source bytes/,
);

addFailureCase(
  'K2S2',
  'true open gap candidate cannot declare source complete',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    makeTrueOpenGapState(path, 'complete');
  },
  /SRC-401 complete source has unreconciled gap review GAP-0401/,
);

addFailureCase(
  'K2S2',
  'open gap candidate cannot name future packet or event ids',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'GAP-0401', (cells) => {
      cells[11] = 'open';
      cells[12] = 'invalid open finding prematurely names canonical reconciliation ids';
    });
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'SRC-401', (cells) => {
      cells[5] = 'blocked';
      cells[7] = 'mutation keeps future canonical ids on an open finding';
    });
    removeSourceWalkExit(path);
  },
  /GAP-0401 open candidate must use proposed_packet_id none and reconciliation_event_id none/,
);

addCase('K2S2', 'reconciliation event must match packet exact-evidence position', (root) => {
  const relativePath = join('docs', 'fixtures', 'source-walk-accounting');
  const path = copyFixture('source-walk-accounting', root, relativePath);
  const span = mdLineSpan(
    join(path, 'corpus', 'sources', 'SRC-401-source-walk.txt'),
    9,
    9,
  );
  if (!span?.bytes) throw new Error('source-walk fixture line 9 is not reopenable');
  const fragmentHash = `sha256:${sha256(span.bytes)}`;
  const evidenceHash = `sha256:${framedExactEvidenceHash([span.bytes])}`;
  const rendered = span.bytes.toString('utf8');
  const renderedHash = `sha256:${sha256(Buffer.from(rendered, 'utf8'))}`;
  updateTableRow(join(path, 'ledgers', 'packet-index.md'), 'PKT-0405', (cells) => {
    cells[2] = 'L9-L9';
    cells[3] = fragmentHash;
    cells[4] = rendered;
  });
  updateTableRow(join(path, 'ledgers', 'packet-index.md'), 'EVID-0404', (cells) => {
    cells[5] = evidenceHash;
  });
  updateTableRow(join(path, 'ledgers', 'packet-index.md'), 'FRAG-0405', (cells) => {
    cells[5] = 'L9-L9';
    cells[8] = fragmentHash;
    cells[9] = span.bytes!.toString('base64');
  });
  updateTableRow(join(path, 'ledgers', 'packet-index.md'), 'XFORM-0404', (cells) => {
    cells[3] = evidenceHash;
    cells[4] = evidenceHash;
    cells[5] = rendered;
    cells[6] = renderedHash;
  });
  const report = requireFailure(runFixture(root, relativePath), 'K2.14');
  requireCheck(report, 'K2.4', 'PASS');
  requireCheck(report, 'K2.13', 'PASS');
  requireCheck(
    report,
    'K2.14',
    'FAIL',
    /EVT-0405 interval 268\.\.319 must be contained in exactly one exact fragment for packet PKT-0405; found 0/,
  );
});

addFailureCase(
  'K2S2',
  'primary walk change invalidates recorded review basis',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'WLK-0402', (cells) => {
      cells[9] = 'primary reviewer recorded no candidate in this interval';
    });
  },
  /GAP-0401 review_basis_digest does not match the current primary review basis/,
);

addFailureCase(
  'K2S2',
  'S1 criteria byte change invalidates recorded review basis',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    appendFileSync(
      join(path, 'ledgers', 'extraction-criteria.md'),
      '\nReview-basis probe note.\n',
    );
  },
  /GAP-0401 review_basis_digest does not match the current primary review basis/,
);

addCase('K2S2', 'primary exact-evidence identity change invalidates review basis', (root) => {
  const relativePath = join('docs', 'fixtures', 'source-walk-accounting');
  const path = copyFixture('source-walk-accounting', root, relativePath);
  const packetIndex = join(path, 'ledgers', 'packet-index.md');
  updateTableRow(packetIndex, 'EVID-0403', (cells) => {
    cells[0] = 'EVID-0493';
  });
  updateTableRow(packetIndex, 'FRAG-0403', (cells) => {
    cells[1] = 'EVID-0493';
  });
  updateTableRow(packetIndex, 'FRAG-0404', (cells) => {
    cells[1] = 'EVID-0493';
  });
  updateTableRow(packetIndex, 'XFORM-0403', (cells) => {
    cells[1] = 'EVID-0493';
  });
  const report = requireFailure(runFixture(root, relativePath), 'K2.14');
  requireCheck(report, 'K2.13', 'PASS');
  requireCheck(
    report,
    'K2.14',
    'FAIL',
    /GAP-0401 review_basis_digest does not match the current primary review basis/,
  );
});

addFailureCase(
  'K2S2',
  'gap review basis cursor must be terminal primary source end',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'GAP-0401', (cells) => {
      cells[4] = 'CUR-0405';
    });
  },
  /GAP-0401 review_basis_cursor_id must identify the terminal primary source-end cursor/,
);

addFailureCase(
  'K2S2',
  'blocked final cursor cannot sit behind committed primary work',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'SRC-401', (cells) => {
      cells[3] = 'CUR-0403';
      cells[5] = 'blocked';
      cells[7] = 'mutation selects a stale shared-position checkpoint';
    });
    removeSourceWalkExit(path);
  },
  /CUR-0403 names shared ordinal 2 as pending but EVT-0402 at ordinal 2 is already committed/,
);

addFailureCase(
  'K2S2',
  'same-position cursor ordinal cannot regress from three to two',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    const packetIndex = join(path, 'ledgers', 'packet-index.md');
    const sourceWalk = join(path, 'ledgers', 'source-walk.md');
    replaceOnce(
      packetIndex,
      '| PKT-0402 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared beta applies. | 1 | active |',
      '| PKT-0402 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared beta applies. | 1 | active |\n'
        + '| PKT-0406 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared beta applies. | 1 | active |',
    );
    replaceOnce(
      packetIndex,
      '| EVID-0402 | PKT-0402 | exact | 1 | single-fragment | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | none | none | none |',
      '| EVID-0402 | PKT-0402 | exact | 1 | single-fragment | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | none | none | none |\n'
        + '| EVID-0405 | PKT-0406 | exact | 1 | single-fragment | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | none | none | none |',
    );
    replaceOnce(
      packetIndex,
      '| FRAG-0402 | EVID-0402 | PKT-0402 | 1 | SRC-401 | L3-L3 | frozen-source | exact-source-bytes | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | U2hhcmVkIGFscGhhIGFwcGxpZXMuIFNoYXJlZCBiZXRhIGFwcGxpZXMuCg== |',
      '| FRAG-0402 | EVID-0402 | PKT-0402 | 1 | SRC-401 | L3-L3 | frozen-source | exact-source-bytes | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | U2hhcmVkIGFscGhhIGFwcGxpZXMuIFNoYXJlZCBiZXRhIGFwcGxpZXMuCg== |\n'
        + '| FRAG-0406 | EVID-0405 | PKT-0406 | 1 | SRC-401 | L3-L3 | frozen-source | exact-source-bytes | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | U2hhcmVkIGFscGhhIGFwcGxpZXMuIFNoYXJlZCBiZXRhIGFwcGxpZXMuCg== |',
    );
    replaceOnce(
      packetIndex,
      '| XFORM-0402 | EVID-0402 | rendered | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | Shared beta applies. | sha256:ff2668d067f317830b464d48794a7b564d815053ac0eb5cbdec000c6b7121e10 |',
      '| XFORM-0402 | EVID-0402 | rendered | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | Shared beta applies. | sha256:ff2668d067f317830b464d48794a7b564d815053ac0eb5cbdec000c6b7121e10 |\n'
        + '| XFORM-0405 | EVID-0405 | rendered | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | sha256:514dc0eda35e86bfa9de89e56c89ec44fa8edabb9eca0a2c204b7c02248b1972 | Shared beta applies. | sha256:ff2668d067f317830b464d48794a7b564d815053ac0eb5cbdec000c6b7121e10 |',
    );
    replaceOnce(
      sourceWalk,
      '| WLK-0403 | SRC-401 | 44 | 87 | admitted | PKT-0401, PKT-0402 |',
      '| WLK-0403 | SRC-401 | 44 | 87 | admitted | PKT-0401, PKT-0402, PKT-0406 |',
    );
    replaceOnce(
      sourceWalk,
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 | PKT-0402 | primary | INV-primary-0401 | committed |',
      '| EVT-0402 | SRC-401 | 44 | 87 | SP-0401 | 2 | PKT-0402 | primary | INV-primary-0401 | committed |\n'
        + '| EVT-0406 | SRC-401 | 44 | 87 | SP-0401 | 3 | PKT-0406 | primary | INV-primary-0401 | committed |',
    );
    replaceOnce(
      sourceWalk,
      '| CUR-0403 | SRC-401 | 44 | SP-0401 | 2 | WLK-0403 | EVT-0401 |',
      '| CUR-0407 | SRC-401 | 44 | SP-0401 | 3 | WLK-0403 | EVT-0402 | sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984 | bounded-pause |\n'
        + '| CUR-0403 | SRC-401 | 44 | SP-0401 | 2 | WLK-0403 | EVT-0401 |',
    );
    refreshReviewBasisDigest(path);
  },
  /CUR-0403 shared-position cursor ordinal regresses from 3 to 2 at SP-0401/,
);

addFailureCase(
  'K2S2',
  'completion gap review ids must be unique',
  'source-walk-accounting',
  'K2.14',
  (path) => {
    updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'SRC-401', (cells) => {
      cells[4] = 'GAP-0401, GAP-0401';
    });
  },
  /SRC-401 gap_review_ids must not contain duplicates/,
);

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

  if (!options.group || ['K2', 'K4/K5'].includes(options.group)) {
    runBaseline(
      'golden run',
      'run-slice-2',
      ['K2.1', 'K2.12', 'K3.1', 'K3.8', 'K4.1', 'K4.6', 'K5.1', 'K5.4', 'K6.10'],
    );
  }
  if (!options.group || options.group === 'K2E') {
    runBaseline(
      'legacy packet behavior',
      'run-slice-2',
      ['K2.13'],
      new Map([
        ['K2.13', /legacy run format \(pre-versioned\) retains K2\.4 behavior/],
      ]),
    );
    runBaseline(
      'explicit 1.0 legacy packet behavior',
      'run-slice-2',
      ['K2.13'],
      new Map([
        ['K2.13', /legacy run format 1\.0\.0-provisional retains K2\.4 behavior/],
      ]),
      (path) => {
        replaceOnce(
          join(path, 'run-manifest.md'),
          '- doctrine_sha: 2dc3549a0c6f3fed660b10743198409945c70b64',
          '- doctrine_sha: 2dc3549a0c6f3fed660b10743198409945c70b64\n'
            + '- run_format_version: 1.0.0-provisional',
        );
      },
    );
    runBaseline(
      'exact evidence',
      'exact-evidence-fragments',
      ['K2.4', 'K2.13'],
    );
  }
  if (!options.group || options.group === 'K2S2') {
    runBaseline(
      'source walk accounting with interrupted primary shared position',
      'source-walk-accounting',
      ['K2.2', 'K2.13', 'K2.14'],
      new Map([
        [
          'K2.14',
          /source walks, shared-position events, next-work cursors, gap reviews, and completion states are structurally valid/,
        ],
      ]),
    );
    runBaseline(
      'uninterrupted primary shared position needs no intermediate cursor',
      'source-walk-accounting',
      ['K2.2', 'K2.13', 'K2.14'],
      new Map([
        [
          'K2.14',
          /source walks, shared-position events, next-work cursors, gap reviews, and completion states are structurally valid/,
        ],
      ]),
      (path) => {
        removeLine(join(path, 'ledgers', 'source-walk.md'), /^\| CUR-0403 \|/);
        updateTableRow(join(path, 'ledgers', 'source-walk.md'), 'CUR-0404', (cells) => {
          cells[8] = 'progress';
        });
      },
    );
    runBaseline(
      'post-review same-position gap reconciliation needs no backdated cursor',
      'source-walk-accounting',
      ['K2.2', 'K2.13', 'K2.14'],
      new Map([
        [
          'K2.14',
          /source walks, shared-position events, next-work cursors, gap reviews, and completion states are structurally valid/,
        ],
      ]),
      (path) => {
        makeSamePositionGapReconciliation(path);
      },
    );
    runBaseline(
      'true open gap candidate remains structurally blocked',
      'source-walk-accounting',
      ['K2.2', 'K2.13', 'K2.14'],
      new Map([
        [
          'K2.14',
          /source walks, shared-position events, next-work cursors, gap reviews, and completion states are structurally valid/,
        ],
      ]),
      (path) => {
        makeTrueOpenGapState(path, 'blocked');
      },
    );
  }
  if (!options.group || options.group === 'K3') {
    runBaseline(
      'evidence roles',
      'evidence-role-adversarial',
      ['K3.1', 'K3.2', 'K3.3', 'K3.4', 'K3.5', 'K3.6', 'K3.7', 'K3.8'],
    );
  }
  if (!options.group || options.group === 'K6') {
    runBaseline(
      'projection',
      'projection-adversarial',
      ['K6.1', 'K6.2', 'K6.3', 'K6.4', 'K6.5', 'K6.6', 'K6.7', 'K6.8', 'K6.9', 'K6.10'],
    );
  }

  const selectedCases = options.group
    ? cases.filter((test) => test.group === options.group)
    : cases;
  for (const test of selectedCases) {
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
const expectedTotal = options.group
  ? EXPECTED_CASES.get(options.group) || 0
  : [...EXPECTED_CASES.values()].reduce((sum, value) => sum + value, 0);
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
