#!/usr/bin/env node

import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateRun } from './validate-run.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const BASE = join(ROOT, 'docs/fixtures/lineage-accounting');
let passed = 0;

function replaceOne(path: string, before: string, after: string): void {
  const text = readFileSync(path, 'utf8');
  const index = text.indexOf(before);
  if (index < 0 || text.indexOf(before, index + before.length) >= 0) {
    throw new Error(`mutation anchor is not unique in ${path}: ${before}`);
  }
  writeFileSync(path, text.slice(0, index) + after + text.slice(index + before.length));
}

function appendText(path: string, text: string): void {
  writeFileSync(path, readFileSync(path, 'utf8') + text);
}

interface FailureExpectation {
  exclusive?: boolean;
  messages?: RegExp[];
}

function checkFailure(
  name: string,
  expectedCheck: string,
  mutate: (run: string) => void,
  expectation: FailureExpectation = {},
): void {
  const temp = mkdtempSync(join(tmpdir(), 'aleph-lineage-mutation-'));
  const run = join(temp, 'run');
  try {
    cpSync(BASE, run, { recursive: true });
    mutate(run);
    const report = validateRun({ root: ROOT, run, kind: 'run' });
    const expectedFailures = report.checks.filter(
      (row) => row.id === expectedCheck && row.status === 'FAIL',
    );
    const failedCheckIds = [...new Set(
      report.checks.filter((row) => row.status === 'FAIL').map((row) => row.id),
    )];
    const missingMessages = (expectation.messages || []).filter(
      (message) => !expectedFailures.some((row) => message.test(row.message)),
    );
    if (
      report.result !== 'FAIL'
      || expectedFailures.length === 0
      || missingMessages.length > 0
      || (
        expectation.exclusive
        && (failedCheckIds.length !== 1 || failedCheckIds[0] !== expectedCheck)
      )
    ) {
      throw new Error(
        `expected ${expectedCheck} failure`
          + `${missingMessages.length > 0 ? ` matching ${missingMessages.join(', ')}` : ''}, `
          + `got ${JSON.stringify(report.checks)}`,
      );
    }
    console.log(`PASS ${name}`);
    passed++;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

function check(name: string, mutate: (run: string) => void): void {
  checkFailure(name, 'K2.15', mutate);
}

function checkPass(name: string, mutate: (run: string) => void): void {
  const temp = mkdtempSync(join(tmpdir(), 'aleph-lineage-positive-'));
  const run = join(temp, 'run');
  try {
    cpSync(BASE, run, { recursive: true });
    mutate(run);
    const report = validateRun({ root: ROOT, run, kind: 'run' });
    const statusCheck = report.checks.find((row) => row.id === 'K2.10');
    if (report.result !== 'PASS' || statusCheck?.status !== 'PASS') {
      throw new Error(`expected PASS including K2.10, got ${JSON.stringify(report.checks)}`);
    }
    console.log(`PASS ${name}`);
    passed++;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

const baseline = validateRun({ root: ROOT, run: BASE, kind: 'run' });
if (baseline.result !== 'PASS') throw new Error(`lineage baseline failed: ${JSON.stringify(baseline.checks)}`);
console.log('PASS baseline 1.3 lineage-current fixture');
passed++;

const lineage = (run: string) => join(run, 'ledgers/lineage.md');
const packets = (run: string) => join(run, 'ledgers/packet-index.md');
const claims = (run: string) => join(run, 'ledgers/claim-inventory.md');
const mergeMap = (run: string) => join(run, 'ledgers/merge-map.md');
const evidenceRoles = (run: string) => join(run, 'ledgers/evidence-roles.md');
const boundaries = (run: string) => join(run, 'ledgers/negative-boundaries.md');
const manifest = (run: string) => join(run, 'run-manifest.md');

checkPass('retracted evidence edge remains legal in 1.3', (run) => replaceOne(
  evidenceRoles(run),
  '|----------|-----------|------|--------------|----------------|------|--------|\n\n## Synthesis/inference markers',
  '|----------|-----------|------|--------------|----------------|------|--------|\n'
    + '| CC-0412 | SRC-401 | contextual | verified-primary | | historical edge withdrawn | retracted:fixture correction |\n\n'
    + '## Synthesis/inference markers',
));
checkPass('retracted merge-map relation remains legal in 1.3', (run) => replaceOne(
  mergeMap(run),
  '| CC-0420 | CC-0418, CC-0419 | historical bad merge retained | SRC-401 | restatement | active |\n',
  '| CC-0420 | CC-0418, CC-0419 | historical bad merge retained | SRC-401 | restatement | active |\n'
    + '| CC-0412 | CC-0402 | withdrawn historical mapping | SRC-401 | restatement | retracted:fixture correction |\n',
));
checkPass('retracted negative-boundary row remains legal in 1.3', (run) => replaceOne(
  boundaries(run),
  '|-------------|----------|------|--------|--------|\n',
  '|-------------|----------|------|--------|--------|\n'
    + '| NB-0401 | CC-0412 | historical-only | withdrawn boundary | retracted:fixture correction |\n',
));
checkFailure('non-active durable packet rejected in 1.3', 'K2.10', (run) => replaceOne(
  packets(run),
  '| PKT-0401 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared alpha applies. | 1 | active |',
  '| PKT-0401 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared alpha applies. | 1 | retracted:unit currentness belongs to lineage |',
), {
  exclusive: true,
  messages: [/PKT-0401 run-format 1\.3 unit rows must use durable status active/],
});
checkFailure('non-active durable claim rejected in 1.3', 'K2.10', (run) => replaceOne(
  claims(run),
  '| CC-0401 | Original claim later split | PKT-0401, PKT-0403 | SRC-401 | factual |  |  |  | | active |',
  '| CC-0401 | Original claim later split | PKT-0401, PKT-0403 | SRC-401 | factual |  |  |  | | retracted:unit currentness belongs to lineage |',
), {
  exclusive: true,
  messages: [/CC-0401 run-format 1\.3 unit rows must use durable status active/],
});
checkFailure('second packet home-definition table rejected in 1.3', 'K2.10', (run) => appendText(
  packets(run),
  '\n## Duplicate packet definitions\n\n'
    + '| packet_id | source_id | locator | span_hash | quote | criterion | status |\n'
    + '|-----------|-----------|---------|-----------|-------|-----------|--------|\n'
    + '| PKT-0401 | SRC-401 | L3-L3 | sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | Shared alpha applies. | 1 | superseded-by:PKT-0402 |\n',
), {
  exclusive: true,
  messages: [
    /requires exactly one canonical packet home-definition table; found 2/,
    /PKT-0401 run-format 1\.3 unit rows must use durable status active/,
  ],
});
checkFailure('second claim home-definition table rejected in 1.3', 'K2.10', (run) => appendText(
  claims(run),
  '\n## Duplicate claim definitions\n\n'
    + '| claim_id | normalized claim | packets | sources | claim_type | disposition | rationale | judged_by | verified | status |\n'
    + '|----------|------------------|---------|---------|------------|-------------|-----------|-----------|----------|--------|\n'
    + '| CC-0401 | Restated durable claim | PKT-0401, PKT-0403 | SRC-401 | factual | | | | | retracted:duplicate table bypass |\n',
), {
  exclusive: true,
  messages: [
    /requires exactly one canonical claim home-definition table; found 2/,
    /CC-0401 run-format 1\.3 unit rows must use durable status active/,
  ],
});
checkFailure('second matching lineage table rejected', 'K2.15', (run) => appendText(
  lineage(run),
  '\n## Duplicate lineage table\n\n'
    + '| lineage_id | owner_stage | type | predecessors | successors | basis | established_by |\n'
    + '|------------|-------------|------|--------------|------------|-------|----------------|\n',
), {
  exclusive: true,
  messages: [/requires exactly one canonical lineage event table; found 2/],
});
checkFailure('second matching lineage table with malformed row rejected', 'K2.15', (run) => appendText(
  lineage(run),
  '\n## Malformed duplicate lineage table\n\n'
    + '| lineage_id | owner_stage | type | predecessors | successors | basis | established_by |\n'
    + '|------------|-------------|------|--------------|------------|-------|----------------|\n'
    + '| not-a-lineage-id | S9 | fuse | none | none | none | none |\n',
), {
  exclusive: true,
  messages: [/requires exactly one canonical lineage event table; found 2/],
});
check('missing lineage artifact', (run) => rmSync(lineage(run)));
check('missing lineage marker', (run) => replaceOne(lineage(run), '- lineage_format: aleph-lineage/v1\n\n', ''));
check('duplicate LIN identity', (run) => replaceOne(lineage(run), '| LIN-0012 |', '| LIN-0001 |'));
check('malformed LIN identity', (run) => replaceOne(lineage(run), '| LIN-0012 |', '| LIN-00X2 |'));
check('invalid lineage type', (run) => replaceOne(lineage(run), '| LIN-0001 | S3 | split |', '| LIN-0001 | S3 | fuse |'));
check('invalid owner stage', (run) => replaceOne(lineage(run), '| LIN-0002 | S3 | replace |', '| LIN-0002 | S5 | replace |'));
check('illegal split cardinality', (run) => replaceOne(lineage(run), 'CC-0410, CC-0411 | original normalization', 'CC-0410 | original normalization'));
check('generic N-to-M shape rejected', (run) => replaceOne(lineage(run), 'CC-0415 | distinct inputs intentionally', 'CC-0415, CC-0416 | distinct inputs intentionally'));
check('lineage self edge', (run) => replaceOne(lineage(run), '| LIN-0002 | S3 | replace | CC-0402 | CC-0412 |', '| LIN-0002 | S3 | replace | CC-0402 | CC-0402 |'));
check('lineage cycle', (run) => replaceOne(lineage(run), 'CC-0416, CC-0417 | later correction', 'CC-0401, CC-0417 | later correction'));
check('predecessor terminalized twice', (run) => replaceOne(lineage(run), '| LIN-0003 | S3 | supersede | CC-0403 |', '| LIN-0003 | S3 | supersede | CC-0402 |'));
checkFailure('terminalized identity cannot be resurrected as a later successor', 'K2.15', (run) => replaceOne(
  lineage(run),
  '| LIN-0003 | S3 | supersede | CC-0403 | CC-0413 |',
  '| LIN-0003 | S3 | supersede | CC-0403 | CC-0401 |',
), {
  exclusive: true,
  messages: [/LIN-0003 resurrects CC-0401 after it was terminalized by LIN-0001/],
});
check('missing predecessor', (run) => replaceOne(lineage(run), '| LIN-0002 | S3 | replace | CC-0402 |', '| LIN-0002 | S3 | replace | CC-0999 |'));
check('orphan successor', (run) => replaceOne(lineage(run), '| LIN-0003 | S3 | supersede | CC-0403 | CC-0413 |', '| LIN-0003 | S3 | supersede | CC-0403 | CC-0999 |'));
check('terminal event with successor', (run) => replaceOne(lineage(run), '| LIN-0006 | S3 | reject | CC-0408 | none |', '| LIN-0006 | S3 | reject | CC-0408 | CC-0412 |'));
check('no-claim applied to claim', (run) => replaceOne(lineage(run), '| LIN-0008 | S3 | no-claim | PKT-0402 | none |', '| LIN-0008 | S3 | no-claim | CC-0408 | none |'));
check('packet to claim encoded as replacement', (run) => replaceOne(lineage(run), '| LIN-0002 | S3 | replace | CC-0402 | CC-0412 |', '| LIN-0002 | S3 | replace | PKT-0401 | CC-0412 |'));
check('merge provenance loss', (run) => replaceOne(claims(run), '| CC-0414 | Canonical duplicate successor | PKT-0401, PKT-0403 |', '| CC-0414 | Canonical duplicate successor | PKT-0401 |'));
check('split aggregate provenance loss', (run) => replaceOne(claims(run), '| CC-0411 | Intermediate split child B | PKT-0403 |', '| CC-0411 | Intermediate split child B | PKT-0401 |'));
check('current claim cites non-current packet', (run) => replaceOne(claims(run), '| CC-0412 | Replacement current claim | PKT-0404 |', '| CC-0412 | Replacement current claim | PKT-0402 |'));
check('silent packet disappearance', (run) => replaceOne(lineage(run), '| LIN-0008 | S3 | no-claim | PKT-0402 | none | packet yields no candidate claim | fixture-simulated-normalizer |\n', ''));
check('legacy 1.2 cannot be reinterpreted as lineage', (run) => replaceOne(manifest(run), '- run_format_version: 1.3.0-provisional', '- run_format_version: 1.2.0-provisional'));
check('source identity cannot enter unit lineage', (run) => replaceOne(lineage(run), '| LIN-0002 | S3 | replace | CC-0402 | CC-0412 |', '| LIN-0002 | S3 | replace | SRC-401 | CC-0412 |'));
check('empty lineage basis rejected', (run) => replaceOne(lineage(run), 'corrected normalization establishes a new identity | fixture-simulated-normalizer', 'none | fixture-simulated-normalizer'));

console.log(`RESULT: PASS (${passed}/${passed})`);
