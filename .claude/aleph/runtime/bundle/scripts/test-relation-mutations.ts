#!/usr/bin/env node

import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseTables } from './lib/markdown.ts';
import {
  parseRelations,
  relationReviewSubjectDigest,
  relationReviewSubjectJson,
  requireRelationWriteWindow,
} from './lib/relations.ts';
import {
  EXACT_EVIDENCE_RUN_FORMAT_VERSION,
  INTERNAL_AMBIGUITY_RUN_FORMAT_VERSION,
  LEGACY_RUN_FORMAT_VERSION,
  LINEAGE_RUN_FORMAT_VERSION,
  RUN_CAPABILITIES,
  SOURCE_WALK_RUN_FORMAT_VERSION,
  TYPED_RELATIONS_RUN_FORMAT_VERSION,
  hasRunCapability,
  loadRun,
} from './lib/run-model.ts';
import { validateRun } from './validate-run.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const BASE = join(ROOT, 'docs/fixtures/typed-relations');
let passed = 0;
let mutationCount = 0;

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

const relations = (run: string) => join(run, 'ledgers/relations.md');
const manifest = (run: string) => join(run, 'run-manifest.md');
const runLog = (run: string) => join(run, 'run-log.md');
const sourceManifest = (run: string) => join(run, 'corpus/manifest.md');
const verifier = (run: string, id: string) => (
  join(run, `verification/harness/S4-relations/${id}.md`)
);

function refreshDigest(run: string, relationId: string): void {
  const model = loadRun(run);
  const row = parseRelations(model).rows.find(
    (candidate) => candidate.values.relationId === relationId,
  );
  if (!row) throw new Error(`cannot refresh missing relation ${relationId}`);
  const prior = row.values.reviewSubjectDigest;
  const next = relationReviewSubjectDigest(row.values);
  replaceOne(relations(run), prior, next);
  replaceOne(verifier(run, row.values.reviewedBy), prior, next);
}

function checkFailure(
  name: string,
  mutate: (run: string) => void,
  messages: RegExp[],
): void {
  const temp = mkdtempSync(join(tmpdir(), 'aleph-relation-mutation-'));
  const run = join(temp, 'run');
  try {
    cpSync(BASE, run, { recursive: true });
    mutate(run);
    const report = validateRun({ root: ROOT, run, kind: 'run' });
    const results = report.checks.filter((row) => row.id === 'K2.16');
    const combined = results.map((row) => row.message).join('\n');
    const missing = messages.filter((message) => !message.test(combined));
    if (
      report.result !== 'FAIL'
      || !results.some((row) => row.status === 'FAIL')
      || missing.length > 0
    ) {
      throw new Error(
        `expected K2.16 failure matching ${messages.join(', ')}, got `
          + JSON.stringify(report.checks),
      );
    }
    console.log(`PASS ${name}`);
    passed++;
    mutationCount++;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

function checkPass(
  name: string,
  mutate: (run: string) => void,
): void {
  const temp = mkdtempSync(join(tmpdir(), 'aleph-relation-positive-'));
  const run = join(temp, 'run');
  try {
    cpSync(BASE, run, { recursive: true });
    mutate(run);
    const report = validateRun({ root: ROOT, run, kind: 'run' });
    if (report.result !== 'PASS') {
      throw new Error(`expected clean run, got ${JSON.stringify(report.checks)}`);
    }
    console.log(`PASS ${name}`);
    passed++;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

const baseline = validateRun({ root: ROOT, run: BASE, kind: 'run' });
if (baseline.result !== 'PASS') {
  throw new Error(`typed-relation baseline failed: ${JSON.stringify(baseline.checks)}`);
}
console.log('PASS baseline 1.4 typed-relation fixture');
passed++;

const cumulative = [
  [LEGACY_RUN_FORMAT_VERSION, ['legacy']],
  [
    EXACT_EVIDENCE_RUN_FORMAT_VERSION,
    ['legacy', 'forward-execution-identity', 'exact-evidence'],
  ],
  [
    SOURCE_WALK_RUN_FORMAT_VERSION,
    ['legacy', 'forward-execution-identity', 'exact-evidence', 'source-walk'],
  ],
  [
    LINEAGE_RUN_FORMAT_VERSION,
    [
      'legacy',
      'forward-execution-identity',
      'exact-evidence',
      'source-walk',
      'lineage',
    ],
  ],
  [
    TYPED_RELATIONS_RUN_FORMAT_VERSION,
    [
      'legacy',
      'forward-execution-identity',
      'exact-evidence',
      'source-walk',
      'lineage',
      'typed-relations',
    ],
  ],
  [
    INTERNAL_AMBIGUITY_RUN_FORMAT_VERSION,
    [
      'legacy',
      'forward-execution-identity',
      'exact-evidence',
      'source-walk',
      'lineage',
      'typed-relations',
      'internal-ambiguity-lifecycle',
    ],
  ],
] as const;
for (const [version, capabilities] of cumulative) {
  for (const capability of RUN_CAPABILITIES) {
    const expected = (capabilities as readonly string[]).includes(capability);
    if (hasRunCapability(version, capability) !== expected) {
      throw new Error(
        `${version} capability ${capability} expected ${expected ? 'present' : 'absent'}`,
      );
    }
  }
}
console.log('PASS cumulative run-format capability registry');
passed++;

const digestVectorRow = parseRelations(loadRun(BASE)).rows.find(
  (row) => row.values.relationId === 'REL-1401',
);
if (!digestVectorRow) throw new Error('REL-1401 review-subject vector is missing');
const expectedSubject = '{"format":"aleph-relation-review-subject/v1",'
  + '"owner_stage":"S4","family":"claim-dependency",'
  + '"type":"semantic-prerequisite","source_kind":"CC","source_id":"CC-0415",'
  + '"target_kind":"CC","target_id":"CC-0412","target_source_id":"none",'
  + '"target_locator":"none","target_span_hash":"none","record_state":"asserted",'
  + '"null_reason":"none","basis_packet_ids":["PKT-0404","PKT-0405"],'
  + '"proposed_by":"invocation:s4-relations-01"}';
if (relationReviewSubjectJson(digestVectorRow.values) !== expectedSubject) {
  throw new Error('REL-1401 review-subject compact JSON bytes or field order changed');
}
if (
  relationReviewSubjectDigest(digestVectorRow.values)
  !== 'sha256:2a449c9d115d3d2e087a02a8548a0b0aee36b3b0e97a7ebf08a1648ae1707b33'
) {
  throw new Error('REL-1401 review-subject digest vector changed');
}
console.log('PASS exact review-subject serialization and digest vector');
passed++;

checkFailure('missing source', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC |', '| CC | CC-0999 | CC |');
  refreshDigest(run, 'REL-1401');
}, [/source CC-0999 does not resolve as CC/]);

checkFailure('missing target', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0415 | CC | CC-0999 |');
  refreshDigest(run, 'REL-1401');
}, [/target CC-0999 does not resolve as CC/]);

checkFailure('wrong source kind', (run) => {
  replaceOne(relations(run), '| semantic-prerequisite | CC | CC-0415 |', '| semantic-prerequisite | SRC | CC-0415 |');
  refreshDigest(run, 'REL-1401');
}, [/source_kind must be CC or PKT/]);

checkFailure('wrong target kind', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0415 | SRC | CC-0412 |');
  refreshDigest(run, 'REL-1401');
}, [/target_kind "SRC" is unsupported/]);

checkFailure('source/target family mismatch', (run) => {
  replaceOne(relations(run), '| claim-dependency | semantic-prerequisite |', '| source-context | semantic-prerequisite |');
  refreshDigest(run, 'REL-1401');
}, [/family\/type mismatch/]);

checkFailure('non-current source', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0402 | CC | CC-0412 |');
  refreshDigest(run, 'REL-1401');
}, [/source CC-0402 is a historical lineage predecessor/]);

checkFailure('non-current target', (run) => {
  replaceOne(relations(run), '| CC | CC-0413 | CC | CC-0412 |', '| CC | CC-0413 | CC | CC-0401 |');
  refreshDigest(run, 'REL-1402');
}, [/target CC-0401 is a historical lineage predecessor/]);

checkFailure('historical predecessor endpoint instead of explicit successor', (run) => {
  replaceOne(relations(run), '| CC | CC-0422 | CC | CC-0421 |', '| CC | CC-0422 | CC | CC-0420 |');
  refreshDigest(run, 'REL-1407');
}, [/target CC-0420 is a historical lineage predecessor/]);

checkFailure('raw prose target', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0415 | CC | prior claim |');
  refreshDigest(run, 'REL-1401');
}, [/target_id must be exactly one CC-<digits> identity/]);

checkFailure('mixed ID and prose target', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0415 | CC | CC-0412 prior claim |');
  refreshDigest(run, 'REL-1401');
}, [/target_id must be exactly one CC-<digits> identity/]);

checkFailure('malformed typed null', (run) => {
  replaceOne(relations(run), '| CC | CC-0421 | null | none |', '| CC | CC-0421 | null | CC-0412 |');
  refreshDigest(run, 'REL-1409');
}, [/requires target_kind null and all target value fields none/]);

checkFailure('null reason and state mismatch', (run) => {
  replaceOne(relations(run), '| explicitly-absent | bounded-review-found-none |', '| explicitly-absent | unresolved-in-frozen-corpus |');
  refreshDigest(run, 'REL-1410');
}, [/explicitly-absent requires null_reason bounded-review-found-none/]);

checkFailure('duplicate REL identity', (run) => {
  replaceOne(relations(run), '| REL-1402 |', '| REL-1401 |');
}, [/REL-1401 is defined more than once/]);

checkFailure('malformed REL identity', (run) => {
  replaceOne(relations(run), '| REL-1401 |', '| REL-14A1 |');
}, [/relation_id must be REL-<digits>/]);

checkFailure('duplicate semantic tuple', (run) => {
  replaceOne(
    relations(run),
    '| REL-1402 | S3 | source-context | antecedent-context | CC | CC-0413 | CC | CC-0412 |',
    '| REL-1402 | S3 | source-context | qualifier-context | CC | CC-0414 | CC | CC-0412 |',
  );
  refreshDigest(run, 'REL-1402');
}, [/duplicates semantic tuple already recorded by REL-1402/]);

checkFailure('explicit absence conflicts with asserted closure', (run) => {
  replaceOne(
    relations(run),
    '| source-context | qualifier-context | CC | CC-0422 | null |',
    '| source-context | qualifier-context | CC | CC-0414 | null |',
  );
  refreshDigest(run, 'REL-1410');
}, [/conflicts between explicit absence and asserted\/unresolved closure/]);

checkFailure('illegal self-edge', (run) => {
  replaceOne(relations(run), '| CC | CC-0415 | CC | CC-0412 |', '| CC | CC-0415 | CC | CC-0415 |');
  refreshDigest(run, 'REL-1401');
}, [/self-edge CC-0415 -> CC-0415 is forbidden/]);

checkFailure('forbidden subtype cycle', (run) => {
  replaceOne(
    relations(run),
    '| REL-1402 | S3 | source-context | antecedent-context | CC | CC-0413 | CC | CC-0412 |',
    '| REL-1402 | S3 | claim-dependency | semantic-prerequisite | CC | CC-0412 | CC | CC-0415 |',
  );
  refreshDigest(run, 'REL-1402');
}, [/semantic-prerequisite prohibited subgraph contains a cycle/]);

checkFailure('forbidden antecedent-context cycle', (run) => {
  replaceOne(
    relations(run),
    '| REL-1404 | S3 | source-context | configuration-context | CC | CC-0412 | CC | CC-0413 |',
    '| REL-1404 | S3 | source-context | antecedent-context | CC | CC-0412 | CC | CC-0413 |',
  );
  refreshDigest(run, 'REL-1404');
}, [/antecedent-context prohibited subgraph contains a cycle/]);

checkFailure('forbidden formal-reference cycle', (run) => {
  replaceOne(
    relations(run),
    '| REL-1412 | S4 | source-context | configuration-context | CC | CC-0417 | CC | CC-0416 |',
    '| REL-1412 | S4 | formal-reference | structural-anchor | CC | CC-0417 | CC | CC-0416 |',
  );
  refreshDigest(run, 'REL-1412');
}, [/formal-reference prohibited subgraph contains a cycle/]);

checkFailure('forbidden continuation-context cycle', (run) => {
  replaceOne(
    relations(run),
    '| REL-1408 | S3 | discourse | parallel-contrast-context | CC | CC-0423 | CC | CC-0414 |',
    '| REL-1408 | S3 | discourse | continuation-context | CC | CC-0421 | CC | CC-0422 |',
  );
  refreshDigest(run, 'REL-1408');
}, [/continuation-context prohibited subgraph contains a cycle/]);

checkFailure('forbidden parallel-contrast-context cycle', (run) => {
  replaceOne(
    relations(run),
    '| REL-1403 | S3 | source-context | qualifier-context | CC | CC-0414 | CC | CC-0412 |',
    '| REL-1403 | S3 | discourse | parallel-contrast-context | CC | CC-0414 | CC | CC-0423 |',
  );
  refreshDigest(run, 'REL-1403');
}, [/parallel-contrast-context prohibited subgraph contains a cycle/]);

checkFailure('malformed locus', (run) => {
  replaceOne(relations(run), '| SRC-401 | L3-L3 |', '| SRC-401 | L0-L3 |');
  refreshDigest(run, 'REL-1405');
}, [/target_locator must be an md-lines/]);

checkFailure('locator incompatible with source scheme', (run) => {
  replaceOne(relations(run), '| SRC-401 | L3-L3 |', '| SRC-401 | page-3 |');
  refreshDigest(run, 'REL-1405');
}, [/target_locator must be an md-lines/]);

checkFailure('locator valid for the wrong known scheme', (run) => {
  replaceOne(relations(run), '| SRC-401 | L3-L3 |', '| SRC-401 | M1 |');
  refreshDigest(run, 'REL-1405');
}, [/target_locator must be an md-lines/]);

checkFailure('declared-but-unverified asserted locus', (run) => {
  replaceOne(sourceManifest(run), '| md-lines |', '| chat-msg |');
  replaceOne(relations(run), '| SRC-401 | L3-L3 |', '| SRC-401 | M1 |');
  refreshDigest(run, 'REL-1405');
}, [/scheme "chat-msg" is declared but not deterministically reopenable/]);

checkFailure('source-locus hash mismatch', (run) => {
  replaceOne(
    relations(run),
    'sha256:5b0ed9a64d05d3b326e2dc22ded33e6da5cba645d01d0d47ed9c64e933f82afb | asserted',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa | asserted',
  );
  refreshDigest(run, 'REL-1405');
}, [/target_span_hash does not match the exact reopened source-locus bytes/]);

checkFailure('relation type and endpoint mismatch', (run) => {
  replaceOne(
    relations(run),
    '| discourse | continuation-context | CC | CC-0422 | CC | CC-0421 |',
    '| discourse | continuation-context | CC | CC-0422 | PKT | PKT-0404 |',
  );
  refreshDigest(run, 'REL-1407');
}, [/relation type\/endpoint mismatch/]);

checkFailure('semantic-prerequisite unresolved target requires CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1409 | S4 | source-context | antecedent-context | CC | CC-0421 | null |',
    '| REL-1409 | S4 | claim-dependency | semantic-prerequisite | PKT | PKT-0405 | null |',
  );
  refreshDigest(run, 'REL-1409');
}, [/claim-dependency\/semantic-prerequisite requires source_kind CC/]);

checkFailure('semantic-prerequisite explicit absence requires CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1410 | S4 | source-context | qualifier-context | CC | CC-0422 | null |',
    '| REL-1410 | S4 | claim-dependency | semantic-prerequisite | PKT | PKT-0405 | null |',
  );
  refreshDigest(run, 'REL-1410');
}, [/claim-dependency\/semantic-prerequisite requires source_kind CC/]);

checkFailure('semantic-prerequisite subtype indeterminate requires CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1411 | S4 | source-context | configuration-context | CC | CC-0423 | null |',
    '| REL-1411 | S4 | claim-dependency | semantic-prerequisite | PKT | PKT-0405 | null |',
  );
  refreshDigest(run, 'REL-1411');
}, [/claim-dependency\/semantic-prerequisite requires source_kind CC/]);

checkFailure('claim-dependency family indeterminate requires CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1413 | S4 | source-context | none | PKT | PKT-0403 | null |',
    '| REL-1413 | S4 | claim-dependency | none | PKT | PKT-0403 | null |',
  );
  refreshDigest(run, 'REL-1413');
}, [/claim-dependency\/none requires source_kind CC/]);

checkPass('semantic-prerequisite typed null accepts CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1409 | S4 | source-context | antecedent-context | CC | CC-0421 | null |',
    '| REL-1409 | S4 | claim-dependency | semantic-prerequisite | CC | CC-0421 | null |',
  );
  refreshDigest(run, 'REL-1409');
});

checkPass('claim-dependency family indeterminate accepts CC source', (run) => {
  replaceOne(
    relations(run),
    '| REL-1413 | S4 | source-context | none | PKT | PKT-0403 | null |',
    '| REL-1413 | S4 | claim-dependency | none | CC | CC-0423 | null |',
  );
  refreshDigest(run, 'REL-1413');
});

checkFailure('missing packet-basis provenance', (run) => {
  replaceOne(relations(run), '| PKT-0404, PKT-0405 | invocation:s4-relations-01 |', '| none | invocation:s4-relations-01 |');
  refreshDigest(run, 'REL-1401');
}, [/basis_packet_ids must be a nonempty ordered/]);

checkFailure('malformed producer reference', (run) => {
  replaceOne(relations(run), '| invocation:s4-relations-01 |', '| fixture producer prose |');
  refreshDigest(run, 'REL-1401');
}, [/proposed_by must use human:<actor-slug> or invocation:<producer-invocation-id>/]);

checkFailure('malformed reviewer reference', (run) => {
  replaceOne(relations(run), '| VER-1401 |', '| verifier-one |');
}, [/reviewed_by must be exactly one VER-<digits> identity/]);

checkFailure('missing verifier record', (run) => {
  unlinkSync(verifier(run, 'VER-1401'));
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 0/]);

checkFailure('moved verifier bytes do not preserve verdict identity', (run) => {
  renameSync(verifier(run, 'VER-1401'), verifier(run, 'VER-9999'));
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 0/]);

checkFailure('different verifier cannot impersonate cited identity through prose', (run) => {
  const source = verifier(run, 'VER-1401');
  const text = readFileSync(source, 'utf8');
  unlinkSync(source);
  writeFileSync(
    verifier(run, 'VER-9999'),
    text.replace('# Verdict VER-1401', '# Verdict VER-9999')
      + '\nVER-1401 was discussed in unrelated rationale.\n',
  );
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 0/]);

checkFailure('verifier basename and heading identity must agree', (run) => {
  replaceOne(verifier(run, 'VER-1401'), '# Verdict VER-1401', '# Verdict VER-9999');
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 0/]);

checkFailure('duplicate canonical verifier identity', (run) => {
  const duplicateDir = join(run, 'verification/harness/S3-relations');
  mkdirSync(duplicateDir, { recursive: true });
  writeFileSync(
    join(duplicateDir, 'VER-1401.md'),
    readFileSync(verifier(run, 'VER-1401')),
  );
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 2/]);

checkPass('unrelated harness prose mention does not duplicate verifier identity', (run) => {
  writeFileSync(
    join(run, 'verification/harness/INDEX.md'),
    '# Harness Index\n\nVER-1401 is listed for navigation only.\n',
  );
});

checkFailure('missing verifier shown field', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    '| shown | exact proposed row, frozen packet basis, current endpoints, and lineage-current inventory |\n',
    '',
  );
}, [/canonical verdict field table requires exactly one nonblank row for: shown/]);

checkFailure('missing verifier withheld field', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    '| withheld | producer rationale, answer keys, external facts, and relation-density targets |\n',
    '',
  );
}, [/canonical verdict field table requires exactly one nonblank row for: withheld/]);

checkFailure('missing verifier lens field', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    '| lens | typed-relation semantic challenge |\n',
    '',
  );
}, [/canonical verdict field table requires exactly one nonblank row for: lens/]);

checkFailure('blank verifier stage field', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    '| stage | S4 relation closure |',
    '| stage | |',
  );
}, [/canonical verdict field table requires exactly one nonblank row for: stage/]);

checkFailure('missing verifier consequence field', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    '| consequence | canonical fixture row may be serialized at the S4 closure barrier |\n',
    '',
  );
}, [/canonical verdict field table requires exactly one nonblank row for: consequence/]);

checkFailure('scratch notes cannot authorize reviewed_by', (run) => {
  const source = verifier(run, 'VER-1401');
  const text = readFileSync(source, 'utf8');
  unlinkSync(source);
  writeFileSync(
    join(run, 'verification/harness/scratch-notes.md'),
    text.replace('# Verdict VER-1401', '# Scratch Notes'),
  );
}, [/reviewed_by VER-1401 must resolve to exactly one verifier verdict; found 0/]);

checkFailure('competing canonical verdict tables are rejected', (run) => {
  const path = verifier(run, 'VER-1401');
  replaceOne(path, '| verdict | upheld |', '| verdict | refuted |');
  replaceOne(
    path,
    '# Verdict VER-1401\n\n',
    '# Verdict VER-1401\n\n'
      + '| field | value |\n'
      + '|-------|-------|\n'
      + '| target | relation-review-subject:sha256:2a449c9d115d3d2e087a02a8548a0b0aee36b3b0e97a7ebf08a1648ae1707b33 |\n'
      + '| lens | decoy typed-relation semantic challenge |\n'
      + '| stage | S4 relation closure |\n'
      + '| shown | decoy proposed row |\n'
      + '| withheld | decoy producer rationale |\n'
      + '| verdict | upheld |\n'
      + '| consequence | decoy canonicalization |\n\n',
  );
}, [/must contain exactly one canonical field \| value verdict table; found 2/]);

checkFailure('malformed review-subject digest', (run) => {
  replaceOne(
    relations(run),
    'sha256:2a449c9d115d3d2e087a02a8548a0b0aee36b3b0e97a7ebf08a1648ae1707b33',
    'sha256:not-a-digest',
  );
}, [/review_subject_digest must be full lowercase sha256:<hex>/]);

checkFailure('digested field changed without a new digest', (run) => {
  replaceOne(relations(run), '| PKT-0404, PKT-0405 | invocation:s4-relations-01 |', '| PKT-0405, PKT-0404 | invocation:s4-relations-01 |');
}, [/review_subject_digest does not match the complete canonical pre-review subject/]);

checkFailure('cited verifier targets a different digest', (run) => {
  replaceOne(
    verifier(run, 'VER-1401'),
    'relation-review-subject:sha256:2a449c9d115d3d2e087a02a8548a0b0aee36b3b0e97a7ebf08a1648ae1707b33',
    'relation-review-subject:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
}, [/VER-1401 target must equal relation-review-subject:sha256:2a449c/]);

checkFailure('refuted verifier cannot authorize a row', (run) => {
  replaceOne(verifier(run, 'VER-1401'), '| verdict | upheld |', '| verdict | refuted |');
}, [/VER-1401 verdict must be upheld, not refuted/]);

checkFailure('cannot-determine verifier cannot authorize a row', (run) => {
  replaceOne(verifier(run, 'VER-1401'), '| verdict | upheld |', '| verdict | cannot-determine |');
}, [/VER-1401 verdict must be upheld, not cannot-determine/]);

checkFailure('family-level indeterminate conflicts with concrete subtype', (run) => {
  replaceOne(
    relations(run),
    '| source-context | none | PKT | PKT-0403 | null |',
    '| source-context | none | CC | CC-0423 | null |',
  );
  refreshDigest(run, 'REL-1413');
}, [/cannot combine family-level indeterminate with a concrete subtype row/]);

checkFailure('subtype indeterminate conflicts with asserted closure', (run) => {
  replaceOne(
    relations(run),
    '| source-context | configuration-context | CC | CC-0423 | null |',
    '| source-context | configuration-context | CC | CC-0412 | null |',
  );
  refreshDigest(run, 'REL-1411');
}, [/conflicts between subtype-scoped indeterminate and asserted closure/]);

checkFailure('taxonomy-level indeterminate conflicts with another source row', (run) => {
  replaceOne(
    relations(run),
    '| none | none | PKT | PKT-0404 | null |',
    '| none | none | CC | CC-0423 | null |',
  );
  refreshDigest(run, 'REL-1414');
}, [/taxonomy-level indeterminate cannot coexist with another relation row/]);

checkFailure('missing relation artifact after S4 closure', (run) => {
  unlinkSync(relations(run));
}, [/requires ledgers\/relations.md once S4 is closed or S5 begins/]);

checkFailure('missing relation marker after S4 closure', (run) => {
  replaceOne(relations(run), '- relation_format: aleph-relations/v1\n\n', '');
}, [/requires relation_format aleph-relations\/v1 exactly once/]);

checkFailure('duplicate relation table', (run) => {
  appendText(
    relations(run),
    '\n## Duplicate canonical relation table\n\n'
      + '| relation_id | owner_stage | family | type | source_kind | source_id | target_kind | target_id | target_source_id | target_locator | target_span_hash | record_state | null_reason | basis_packet_ids | proposed_by | review_subject_digest | reviewed_by |\n'
      + '|-------------|-------------|--------|------|-------------|-----------|-------------|-----------|------------------|----------------|------------------|--------------|-------------|------------------|-------------|-----------------------|-------------|\n',
  );
}, [/requires exactly one canonical 17-column relation table/]);

checkFailure('canonical row retained before S4 closure', (run) => {
  replaceOne(
    manifest(run),
    '| 4 | ASSEMBLED | 2026-08-14 09:20 UTC | manual-fixture-assembler | structural lineage-current relation fixture assembled after the S4 closure barrier |\n',
    '',
  );
  replaceOne(runLog(run), '— S4 — exit', '— S4 — review');
  replaceOne(runLog(run), '— S5 — entry', '— S4 — checkpoint');
}, [/retained pre-S4-closure state may contain only the marker and an empty/]);

checkFailure('support/evidence field added to relation table', (run) => {
  replaceOne(
    relations(run),
    '| relation_id | owner_stage | family | type | source_kind | source_id | target_kind | target_id | target_source_id | target_locator | target_span_hash | record_state | null_reason | basis_packet_ids | proposed_by | review_subject_digest | reviewed_by |',
    '| relation_id | owner_stage | family | type | source_kind | source_id | target_kind | target_id | target_source_id | target_locator | target_span_hash | record_state | null_reason | basis_packet_ids | proposed_by | review_subject_digest | reviewed_by | support |',
  );
  replaceOne(
    relations(run),
    '|-------------|-------------|--------|------|-------------|-----------|-------------|-----------|------------------|----------------|------------------|--------------|-------------|------------------|-------------|-----------------------|-------------|',
    '|-------------|-------------|--------|------|-------------|-----------|-------------|-----------|------------------|----------------|------------------|--------------|-------------|------------------|-------------|-----------------------|-------------|---------|',
  );
}, [/forbidden support\/evidence-role field/, /exact adopted 17-column schema/]);

checkFailure('1.3 cannot be interpreted as 1.4', (run) => {
  replaceOne(
    manifest(run),
    '- run_format_version: 1.4.0-provisional',
    '- run_format_version: 1.3.0-provisional',
  );
}, [/run format 1\.3\.0-provisional must not be reinterpreted as aleph-relations\/v1/]);

checkFailure('S2 cannot own a claim-source proposal', (run) => {
  replaceOne(
    relations(run),
    '| REL-1402 | S3 | source-context | antecedent-context |',
    '| REL-1402 | S2 | source-context | antecedent-context |',
  );
  refreshDigest(run, 'REL-1402');
}, [/S2 relation proposals require a PKT source/]);

checkFailure('unknown relation state is closed out', (run) => {
  replaceOne(
    relations(run),
    '| REL-1401 | S4 | claim-dependency | semantic-prerequisite | CC | CC-0415 | CC | CC-0412 | none | none | none | asserted |',
    '| REL-1401 | S4 | claim-dependency | semantic-prerequisite | CC | CC-0415 | CC | CC-0412 | none | none | none | ACTIVE |',
  );
  refreshDigest(run, 'REL-1401');
}, [/record_state "ACTIVE" is unsupported/]);

checkFailure('not-applicable remains review-only', (run) => {
  replaceOne(
    relations(run),
    '| REL-1410 | S4 | source-context | qualifier-context | CC | CC-0422 | null | none | none | none | none | explicitly-absent |',
    '| REL-1410 | S4 | source-context | qualifier-context | CC | CC-0422 | null | none | none | none | none | not-applicable |',
  );
  refreshDigest(run, 'REL-1410');
}, [/record_state "not-applicable" is unsupported/]);

let temporalBytes = 'marker-and-empty-table';
try {
  requireRelationWriteWindow('before-s4-closure');
  temporalBytes += '\nREL-before';
  throw new Error('pre-closure relation write unexpectedly succeeded');
} catch (error) {
  if (!/forbidden during before-s4-closure/.test(String(error))) throw error;
}
if (temporalBytes !== 'marker-and-empty-table') {
  throw new Error('pre-closure refusal changed bytes');
}
console.log('PASS temporal pre-closure refusal preserves bytes');
passed++;

requireRelationWriteWindow('s4-closure');
temporalBytes += '\nREL-at-closure';
if (!temporalBytes.endsWith('REL-at-closure')) {
  throw new Error('S4 closure write was not permitted');
}
console.log('PASS temporal S4-closure write window');
passed++;

const postClosureBytes = temporalBytes;
try {
  requireRelationWriteWindow('after-s4-closure');
  temporalBytes += '\nREL-after';
  throw new Error('post-closure relation write unexpectedly succeeded');
} catch (error) {
  if (!/forbidden during after-s4-closure/.test(String(error))) throw error;
}
if (temporalBytes !== postClosureBytes) {
  throw new Error('post-closure refusal changed bytes');
}
console.log('PASS temporal post-closure refusal preserves bytes');
passed++;

const semanticText = readFileSync(
  join(BASE, 'verification/semantic-review-cases.md'),
  'utf8',
);
const semanticTable = parseTables(semanticText, 'verification/semantic-review-cases.md')
  .find((table) => table.normalizedHeader[0] === 'case id');
const requiredChallenges = new Set([
  'missing required relation',
  'over-broad relation',
  'wrong structurally legal subtype',
  'wrong existing/current target',
  'context misused as support',
  'qualifier/antecedent loss',
  'unjustified permitted cycle',
  'exact legal locus aimed at wrong semantic span',
  'invented outside-corpus target disguised as in-corpus',
  'explicit absence from incomplete context',
]);
if (!semanticTable) throw new Error('semantic-review case table is missing');
for (const row of semanticTable.rows) {
  if (requiredChallenges.has(row.cells[1]) && row.cells[3] === 'refuted') {
    requiredChallenges.delete(row.cells[1]);
  }
}
if (requiredChallenges.size > 0) {
  throw new Error(`semantic-review challenge cases missing: ${[...requiredChallenges].join(', ')}`);
}
console.log('PASS retained semantic-review challenge set remains outside K2');
passed++;

console.log(`RESULT: PASS (${passed}/${passed}; ${mutationCount} deterministic mutations)`);
