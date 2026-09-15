#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  LIMITATION_HEADERS, REPRESENTATION_PATH, REPRESENTATION_USE_PATH,
  materialFeatureAvailable, materialFragmentsHash, materialHash, materialTableMarkdown,
  parseRepresentationInventory, parseSuppliedRepresentation, prepareRepresentationCapture,
  readRepresentationContext, representationMarkdown, representationUseDigest,
  representationUsesMarkdown, representationLimitations, materialReviewUseState, validateMaterialUseInput, type MaterialRow,
} from './lib/source-representation.ts';
import { sourceWalkReviewBasisDigest } from './lib/checks-k2.ts';
import { hasRunCapability, loadRun, SUPPORTED_RUN_FORMAT_VERSIONS } from './lib/run-model.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const FAMILY = join(ROOT, 'docs/fixtures/formal-layout-bindings');
const POSITIVE = join(FAMILY, 'positive');
const INPUTS = join(FAMILY, 'inputs');
const TEMP = mkdtempSync(join(tmpdir(), 'aleph-representation-mutations-'));
const reports: Array<{ name: string; result: string; token?: string }> = [];
const source = readFileSync(join(INPUTS, 'material.txt'));
const descriptor = () => parseSuppliedRepresentation(readFileSync(join(INPUTS, 'table.aleph-representation.json')));
let serial = 0;
function directory(name: string): string {
  const path = join(TEMP, `${++serial}-${name}`);
  mkdirSync(path, { recursive: true });
  return path;
}
function cli(run: string, token?: string, checkId = 'K2.18'): void {
  const invocation = spawnSync(process.execPath, [join(ROOT, 'scripts/validate-run.ts'), '--root', TEMP, '--run', run, '--json'], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  assert.equal(invocation.error, undefined, invocation.error?.message);
  const report = JSON.parse(invocation.stdout);
  const runtime = spawnSync(process.execPath, [join(ROOT, 'runtime-js/scripts/validate-run.js'), '--root', TEMP, '--run', run, '--json'], {
    encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  });
  assert.equal(runtime.error, undefined, runtime.error?.message);
  assert.equal(runtime.status, invocation.status, runtime.stderr);
  assert.deepEqual(JSON.parse(runtime.stdout), report, 'source/runtime behavioral drift');
  if (token) {
    assert.notEqual(invocation.status, 0, JSON.stringify(report));
    assert(report.checks.some((c: { id: string; status: string; message: string }) =>
      c.id === checkId && c.status === 'FAIL' && c.message.includes(token)), JSON.stringify(report.checks.filter((c: { status: string }) => c.status === 'FAIL')));
  } else {
    assert.equal(invocation.status, 0, JSON.stringify(report.checks.filter((c: { status: string }) => c.status === 'FAIL')));
    assert.equal(report.result, 'PASS');
  }
}
function test(name: string, fn: () => void, token?: string): void {
  fn();
  reports.push({ name, result: 'PASS', ...(token ? { token } : {}) });
  console.log(`PASS ${name}${token ? ` [K2.18 ${token}]` : ''}`);
}
function copyPositive(name: string): string {
  const run = directory(name);
  cpSync(POSITIVE, run, { recursive: true });
  return run;
}
function writeInventory(run: string, mutate: (inventory: ReturnType<typeof parseRepresentationInventory>) => void, seal = true): void {
  const inventory = parseRepresentationInventory(readFileSync(join(run, REPRESENTATION_PATH), 'utf8'));
  mutate(inventory);
  const text = representationMarkdown(inventory);
  writeFileSync(join(run, REPRESENTATION_PATH), text);
  if (seal) {
    const manifest = join(run, 'run-manifest.md');
    writeFileSync(manifest, readFileSync(manifest, 'utf8').replace(/representation_inventory_hash: sha256:[0-9a-f]{64}/u,
      `representation_inventory_hash: ${materialHash(text)}`));
  }
}
function frozen(name: string, raw = descriptor(), bytes = source, assets = new Map<string, Buffer>()): string {
  const run = directory(name);
  mkdirSync(join(run, 'corpus/sources'), { recursive: true });
  const captured = prepareRepresentationCapture([{ source_id: 'SRC-401', bytes, descriptor: Buffer.from(JSON.stringify(raw)), assets }]);
  writeFileSync(join(run, 'corpus/sources/material.bin'), bytes);
  const inventory = representationMarkdown(captured.inventory);
  writeFileSync(join(run, REPRESENTATION_PATH), inventory);
  for (const [path, data] of captured.assets) {
    mkdirSync(dirname(join(run, path)), { recursive: true });
    writeFileSync(join(run, path), data);
  }
  const model = loadRun(POSITIVE);
  const previousHash = model.corpus.sources[0].values.contentHash;
  const manifest = readFileSync(join(POSITIVE, 'run-manifest.md'), 'utf8')
    .replaceAll(previousHash, materialHash(bytes))
    .replace(/^.*\| (DISTILLING|ASSEMBLED) \|.*\n/gmu, '')
    .replace(/representation_inventory_hash: sha256:[0-9a-f]{64}/u, `representation_inventory_hash: ${materialHash(inventory)}`);
  writeFileSync(join(run, 'run-manifest.md'), manifest);
  writeFileSync(join(run, 'run-log.md'), '# Run Log — RUN-typed-relations\n\n## 2026-08-14 08:00 UTC — S0 — entry\n\nSynthetic input.\n\n## 2026-08-14 08:05 UTC — S0 — exit\n\nFixture-simulated scope freeze only.\n');
  writeFileSync(join(run, 'corpus/manifest.md'), '# Corpus Manifest\n\n'
    + '| source_id | kind | locus | scheme | content_hash | date(s) | trust_class | sensitivity | admission note |\n'
    + '| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
    + `| SRC-401 | design-note | sources/material.bin | ${captured.sourceSchemes.get('SRC-401')} | ${materialHash(bytes)} | 2026-09-11 | model-generated | none | bounded synthetic capture |\n`);
  return run;
}
function sealedUses(run: string, rows: MaterialRow[]): void {
  const text = representationUsesMarkdown(rows);
  writeFileSync(join(run, REPRESENTATION_USE_PATH), text);
  const path = join(run, 'run-log.md');
  writeFileSync(path, readFileSync(path, 'utf8').replace(/representation_use_closure_hash: sha256:[0-9a-f]{64}/u, `representation_use_closure_hash: ${materialHash(text)}`));
}
function useMutation(name: string, token: string, mutate: (row: MaterialRow) => void): void {
  test(name, () => {
    const run = copyPositive(name), context = readRepresentationContext(loadRun(run));
    mutate(context.uses[0]);
    sealedUses(run, context.uses);
    cli(run, token);
  }, token);
}
function inventoryMutation(name: string, token: string, mutate: (inventory: ReturnType<typeof parseRepresentationInventory>) => void): void {
  test(name, () => { const run = frozen(name); writeInventory(run, mutate); cli(run, token); }, token);
}
function replaceAsset(run: string, id: string, bytes: Buffer): void {
  const inventory = parseRepresentationInventory(readFileSync(join(run, REPRESENTATION_PATH), 'utf8'));
  const asset = inventory.assets.find((a) => a.asset_id === id)!;
  writeFileSync(join(run, asset.locus), bytes);
  writeInventory(run, (inv) => {
    const row = inv.assets.find((a) => a.asset_id === id)!;
    row.byte_length = String(bytes.length); row.content_hash = materialHash(bytes);
  });
}
function refreshFixtureBindings(run: string): void {
  const model = loadRun(run), context = readRepresentationContext(model);
  for (const row of context.uses) row.review_subject_digest = representationUseDigest(model, context, row);
  sealedUses(run, context.uses);
  const walkPath = join(run, 'ledgers/source-walk.md');
  let walk = readFileSync(walkPath, 'utf8');
  for (const row of model.sourceWalk.gapReviews) walk = walk.replaceAll(row.values.reviewBasisDigest,
    sourceWalkReviewBasisDigest(model, row.values.sourceId, row.values.reviewBasisCursorId)!);
  writeFileSync(walkPath, walk);
  const precis = join(run, 'precis.md');
  writeFileSync(precis, readFileSync(precis, 'utf8').replace(materialTableMarkdown(LIMITATION_HEADERS, []),
    materialTableMarkdown(LIMITATION_HEADERS, representationLimitations(model, context))));
}
function rebindDeclaration(raw: ReturnType<typeof descriptor>, bytes: Buffer): void {
  for (const binding of raw.bindings) {
    const fragment = bytes.subarray(Number(binding.start_byte), Number(binding.end_byte));
    binding.fragment_hash = materialHash(fragment); binding.exact_bytes_base64 = fragment.toString('base64');
  }
  for (const object of raw.objects) if ((object.binding_ids as string[]).length) {
    object.content_hash = materialFragmentsHash((object.binding_ids as string[]).map((id) => {
      const binding = raw.bindings.find((b) => b.binding_id === id)!;
      return bytes.subarray(Number(binding.start_byte), Number(binding.end_byte));
    }));
  }
}

try {
  test('FX15 cumulative 1.6 text-only PKT/CC/REL receipts', () => cli(POSITIVE));
  test('FX01 supplied table spans, two header levels, caption and empty cell', () => cli(frozen('table')));
  test('FX02 coherent semantic header shift remains structural PASS', () => {
    const raw = descriptor();
    const headers = raw.objects.filter((o) => o.kind === 'header').map((o) => String(o.object_id));
    for (const a of raw.associations.filter((a) => a.kind === 'header-for')) a.target_ids = [headers[0], headers[2]];
    cli(frozen('coherent-shift', raw));
  });
  inventoryMutation('FX02 inconsistent retained shifted cell', 'COORDINATE', (inv) => {
    const cell = inv.objects.find((o) => o.kind === 'cell')!;
    cell.coordinates = JSON.stringify({ row_ids: ['OBJ-9999'], column_ids: ['OBJ-9998'] });
  });
  test('FX03 flattened text retained and formal structure unavailable', () => {
    const run = frozen('flattened'); cli(run);
    const ctx = readRepresentationContext(loadRun(run)), o = ctx.inventory.objects.find((o) => o.kind === 'formal')!;
    assert.equal(materialFeatureAvailable(ctx, { object_id: o.object_id, feature: 'formal-structure', binding_ids: [] }), false);
    assert.equal(materialFeatureAvailable(ctx, { object_id: o.object_id, feature: 'text-bytes', binding_ids: JSON.parse(o.binding_ids) }), true);
  });
  test('FX04 image-only chart has no machine-readable values', () => {
    const raw = descriptor(), bytes = Buffer.from([0, 255, 137, 80, 78, 71]), log = Buffer.from('synthetic supplied image; no values');
    raw.assets.push(
      { asset_id: 'AST-0001', role: 'rendered-image', input_path: 'image.bin', media_type: 'image/png', encoding: 'opaque', byte_length: String(bytes.length), content_hash: materialHash(bytes) },
      { asset_id: 'AST-0002', role: 'render-log', input_path: 'image-log.txt', media_type: 'text/plain', encoding: 'utf8', byte_length: String(log.length), content_hash: materialHash(log) },
    );
    raw.provenance.push({ provenance_id: 'RPR-0002', type: 'supplied-rendering', actor: 'synthetic fixture', tool: 'unknown', tool_version: 'unknown',
      input_refs: ['source'], output_refs: ['AST-0001', 'AST-0002'], parameters_asset_id: 'AST-0002', declaration_asset_id: 'AST-0002' });
    raw.bindings.push({ binding_id: 'BND-0100', carrier_id: 'AST-0001', start_byte: '0', end_byte: String(bytes.length), page_id: 'none', region_id: 'none',
      byte_role: 'retained-asset-bytes', fragment_hash: materialHash(bytes), exact_bytes_base64: bytes.toString('base64') });
    raw.objects.push(
      { object_id: 'OBJ-0100', kind: 'figure', parent_id: 'OBJ-0001', state: 'unsupported', reason: 'no supplied chart values', provenance_id: 'RPR-0001',
        binding_ids: [], content_hash: 'none', coordinates: { figure_kind: 'chart', image_ids: ['OBJ-0101'], values_ids: [], values_state: 'unsupported' } },
      { object_id: 'OBJ-0101', kind: 'image', parent_id: 'OBJ-0100', state: 'available', reason: 'none', provenance_id: 'RPR-0002',
        binding_ids: ['BND-0100'], content_hash: materialFragmentsHash([bytes]), coordinates: {} },
    );
    raw.associations.push({ association_id: 'ASC-0100', kind: 'caption-for', subject_id: 'OBJ-0100', target_ids: [], state: 'degraded', reason: 'source-declares-absent', provenance_id: 'RPR-0001' });
    const run = frozen('image-only', raw, source, new Map([['image.bin', bytes], ['image-log.txt', log]])); cli(run);
    const ctx = readRepresentationContext(loadRun(run)), figure = ctx.inventory.objects.find((o) => o.kind === 'figure')!;
    assert.equal(materialFeatureAvailable(ctx, { object_id: figure.object_id, feature: 'chart-values', binding_ids: [] }), false);
  });
  test('FX05 honest opaque capture PASS; attempted S2 FAIL', () => {
    const raw = descriptor(), bytes = readFileSync(join(INPUTS, 'opaque.bin'));
    raw.extraction_surface = 'opaque'; raw.state = 'unsupported'; raw.reason = 'opaque extraction unsupported';
    raw.assets = []; raw.objects = [raw.objects[0]]; raw.associations = [];
    raw.objects[0].content_hash = materialFragmentsHash([bytes]);
    raw.bindings = [{ binding_id: 'BND-0001', carrier_id: 'source', start_byte: '0', end_byte: String(bytes.length), page_id: 'none', region_id: 'none',
      byte_role: 'frozen-source-bytes', fragment_hash: materialHash(bytes), exact_bytes_base64: bytes.toString('base64') }];
    const run = frozen('opaque', raw, bytes); cli(run);
    writeFileSync(join(run, 'run-log.md'), readFileSync(join(run, 'run-log.md'), 'utf8') + '\n## 2026-08-14 08:20 UTC — S2 — entry\n');
    cli(run, 'UNSUPPORTED_EXTRACTION_SURFACE'); cli(run, 'UNSUPPORTED_EXTRACTION_SURFACE');
  }, 'UNSUPPORTED_EXTRACTION_SURFACE');
  useMutation('FX06 unknown-origin capture cannot claim exact-representation', 'FIDELITY', (r) => { r.fidelity_claim = 'exact-representation'; });
  useMutation('FX06 forbidden gold assertion', 'FIDELITY', (r) => { r.fidelity_claim = 'gold'; });
  useMutation('unavailable interpretation cannot manufacture a canonical packet receipt', 'USE_CLOSURE', (r) => {
    r.use_state = 'CANNOT_DETERMINE'; r.reason = 'Required structure is unavailable.';
    r.limitation_refs = JSON.stringify([JSON.parse(r.requirements)[0].object_id]);
  });
  test('available original capture permits bounded exact-representation fidelity', () => {
    const run = copyPositive('available-fidelity');
    writeInventory(run, (inv) => { inv.representations[0].origin_kind = 'original-capture'; });
    const ctx = readRepresentationContext(loadRun(run)); ctx.uses[0].fidelity_claim = 'exact-representation';
    sealedUses(run, ctx.uses); refreshFixtureBindings(run); cli(run);
  });
  test('honestly degraded capture PASS but degraded-as-exact FAIL', () => {
    const run = copyPositive('degraded-fidelity');
    writeInventory(run, (inv) => {
      inv.representations[0].origin_kind = 'original-capture';
      inv.representations[0].state = 'degraded'; inv.representations[0].reason = 'Supplied layout is incomplete.';
    });
    refreshFixtureBindings(run); cli(run);
    const ctx = readRepresentationContext(loadRun(run)); ctx.uses[0].fidelity_claim = 'exact-representation';
    ctx.uses[0].review_subject_digest = representationUseDigest(loadRun(run), ctx, ctx.uses[0]);
    sealedUses(run, ctx.uses); cli(run, 'FIDELITY');
  }, 'FIDELITY');
  inventoryMutation('FX07 missing declared header', 'ASSOCIATION', (inv) => { inv.associations[0].target_ids = '["OBJ-9999"]'; });
  inventoryMutation('FX08 colliding cell coordinates', 'COORDINATE', (inv) => {
    const cells = inv.objects.filter((o) => o.kind === 'cell'); cells[1].coordinates = cells[0].coordinates;
  });
  inventoryMutation('FX09 changed exact cell bytes', 'BINDING', (inv) => { inv.bindings[1].exact_bytes_base64 = Buffer.from('changed').toString('base64'); });
  inventoryMutation('FX10 absent declaration provenance', 'PROVENANCE', (inv) => { inv.objects.find((o) => o.kind === 'table')!.provenance_id = 'RPR-9999'; });
  useMutation('FX11 undeclared chart values in usable request', 'UNDECLARED_FEATURE', (r) => {
    const req = JSON.parse(r.requirements); req[0].feature = 'chart-values'; r.requirements = JSON.stringify(req);
  });
  test('FX12 ordered discontiguous fragments are length framed', () => {
    const raw = descriptor(), formal = raw.objects.find((o) => o.kind === 'formal')!;
    const bs = raw.bindings.slice(1, 3);
    formal.binding_ids = bs.map((b) => b.binding_id);
    formal.content_hash = materialFragmentsHash(bs.map((b) => source.subarray(Number(b.start_byte), Number(b.end_byte))));
    cli(frozen('ordered', raw));
    const run = frozen('ordered-mutation', raw);
    writeInventory(run, (inv) => {
      const o = inv.objects.find((o) => o.kind === 'formal')!;
      o.binding_ids = JSON.stringify(JSON.parse(o.binding_ids).reverse());
    });
    cli(run, 'BINDING');
  }, 'BINDING');
  test('FX13 unavailable header and candidate caption remain visible', () => {
    const raw = descriptor();
    raw.associations[0].state = 'degraded'; raw.associations[0].target_ids = []; raw.associations[0].reason = 'source-declares-absent';
    const caption = raw.associations.find((a) => a.kind === 'caption-for')!;
    const candidate = raw.objects.find((o) => o.kind === 'caption')!;
    raw.objects.push({ ...candidate, object_id: 'OBJ-0310' });
    caption.target_ids = [...caption.target_ids as string[], 'OBJ-0310'];
    caption.state = 'indeterminate'; caption.reason = 'supplied caption candidates unresolved';
    cli(frozen('candidates', raw));
  });
  test('known empty cell and honestly unavailable cell both retain truthful structure', () => {
    cli(frozen('empty-cell'));
    const raw = descriptor(), cell = raw.objects.find((o) => o.object_id === 'OBJ-0015')!;
    cell.state = 'unsupported'; cell.reason = 'Cell bytes were not supplied.';
    cell.binding_ids = []; cell.content_hash = 'none';
    cli(frozen('unavailable-cell', raw));
  });
  test('different supplied formal strings do not acquire semantic checker verdicts', () => {
    for (const formalText of ['x+y = z', 'x-y = z']) {
      const raw = descriptor(), bytes = Buffer.from(source.toString('utf8').replace('x2 + y2', formalText));
      rebindDeclaration(raw, bytes);
      const formal = raw.objects.find((o) => o.kind === 'formal')!;
      formal.state = 'available'; formal.reason = 'none';
      formal.coordinates = { notation: 'source-markup', structure_ids: [], structure_state: 'available' };
      cli(frozen('formal-variant', raw, bytes));
    }
  });
  test('alternate supplied captions and cell values remain structurally valid', () => {
    const raw = descriptor(), bytes = Buffer.from(source.toString('utf8').replace('Quarterly', 'Alternate').replace('\n8\n13\n', '\n9\n21\n'));
    assert(!bytes.equals(source)); rebindDeclaration(raw, bytes);
    cli(frozen('caption-values-variant', raw, bytes));
  });
  test('alternate explicitly supplied chart values remain available without image inference', () => {
    for (const number of ['13', '21']) {
      const raw = descriptor(), bytes = Buffer.from(source.toString('utf8').replace('\n13\n', `\n${number}\n`));
      rebindDeclaration(raw, bytes);
      raw.objects.push(
        { object_id: 'OBJ-0300', kind: 'figure', parent_id: 'OBJ-0001', state: 'available', reason: 'none',
          provenance_id: 'RPR-0001', binding_ids: [], content_hash: 'none',
          coordinates: { figure_kind: 'chart', image_ids: [], values_ids: ['OBJ-0301'], values_state: 'available' } },
        { object_id: 'OBJ-0301', kind: 'chart-values', parent_id: 'OBJ-0300', state: 'available', reason: 'none',
          provenance_id: 'RPR-0001', binding_ids: ['BND-0006'],
          content_hash: materialFragmentsHash([Buffer.from(number)]), coordinates: {} },
      );
      raw.associations.push({ association_id: 'ASC-0300', kind: 'caption-for', subject_id: 'OBJ-0300',
        target_ids: ['OBJ-0019'], state: 'available', reason: 'none', provenance_id: 'RPR-0001' });
      const run = frozen('declared-chart-values', raw, bytes); cli(run);
      const context = readRepresentationContext(loadRun(run)), figure = context.inventory.objects.find((o) => o.kind === 'figure')!;
      assert(materialFeatureAvailable(context, { object_id: figure.object_id, feature: 'chart-values', binding_ids: [] }));
    }
  });
  test('ordered cross-page fragments preserve explicit order without a reading-order inference', () => {
    const raw = descriptor();
    for (const [id, index] of [['OBJ-0300', 1], ['OBJ-0301', 2]] as const) {
      const binding = raw.bindings[index], bytes = source.subarray(Number(binding.start_byte), Number(binding.end_byte));
      raw.objects.push({ object_id: id, kind: 'page', parent_id: 'OBJ-0001', state: 'available', reason: 'none',
        provenance_id: 'RPR-0001', binding_ids: [binding.binding_id], content_hash: materialFragmentsHash([bytes]),
        coordinates: { index, label: null, space: null } });
    }
    const fragments = raw.bindings.slice(1, 3);
    fragments[0].page_id = 'OBJ-0300'; fragments[1].page_id = 'OBJ-0301';
    const formal = raw.objects.find((o) => o.kind === 'formal')!;
    formal.binding_ids = fragments.map((b) => b.binding_id);
    formal.content_hash = materialFragmentsHash(fragments.map((b) => source.subarray(Number(b.start_byte), Number(b.end_byte))));
    cli(frozen('cross-page', raw));
  });
  test('FX14 exact CRLF/entity/spacing/multibyte bytes remain unchanged', () => {
    const run = frozen('exact-bytes'); cli(run);
    assert(readFileSync(join(run, 'corpus/sources/material.bin')).equals(source));
    assert(source.includes(Buffer.from('\\r\\n'.replace('\\r', '\r').replace('\\n', '\n'))));
    assert(source.includes(Buffer.from('&amp;')) && source.includes(Buffer.from('  Ω')));
  });
  test('FX16 formats 1.0–1.5 do not activate material capability', () => {
    const firstMaterial = SUPPORTED_RUN_FORMAT_VERSIONS.indexOf('1.6.0-provisional');
    for (const version of SUPPORTED_RUN_FORMAT_VERSIONS.slice(0, firstMaterial)) assert.equal(hasRunCapability(version, 'formal-layout-bindings'), false);
    for (const version of SUPPORTED_RUN_FORMAT_VERSIONS.slice(firstMaterial)) assert.equal(hasRunCapability(version, 'formal-layout-bindings'), true);
    assert.equal(hasRunCapability('99.0.0-provisional', 'formal-layout-bindings'), false);
  });
  test('FX17 rendered formal export has independent asset identity', () => {
    const raw = descriptor(), rendered = Buffer.from('x² + y²'), log = Buffer.from('synthetic renderer receipt; settings unknown');
    raw.assets.push(
      { asset_id: 'AST-0001', role: 'rendered-text', input_path: 'rendered.txt', media_type: 'text/plain', encoding: 'utf8', byte_length: String(rendered.length), content_hash: materialHash(rendered) },
      { asset_id: 'AST-0002', role: 'render-log', input_path: 'render-log.txt', media_type: 'text/plain', encoding: 'utf8', byte_length: String(log.length), content_hash: materialHash(log) },
    );
    raw.provenance.push({ provenance_id: 'RPR-0002', type: 'supplied-rendering', actor: 'synthetic fixture', tool: 'unknown', tool_version: 'unknown',
      input_refs: ['source'], output_refs: ['AST-0001', 'AST-0002'], parameters_asset_id: 'AST-0002', declaration_asset_id: 'AST-0002' });
    raw.bindings.push({ binding_id: 'BND-0100', carrier_id: 'AST-0001', start_byte: '0', end_byte: String(rendered.length), page_id: 'none', region_id: 'none',
      byte_role: 'retained-asset-bytes', fragment_hash: materialHash(rendered), exact_bytes_base64: rendered.toString('base64') });
    const formal = raw.objects.find((o) => o.kind === 'formal')!;
    formal.coordinates = { notation: 'renderer-export', structure_ids: ['OBJ-0100'], structure_state: 'available' };
    raw.objects.push({ object_id: 'OBJ-0100', kind: 'text', parent_id: formal.object_id, state: 'available', reason: 'none',
      provenance_id: 'RPR-0002', binding_ids: ['BND-0100'], content_hash: materialFragmentsHash([rendered]), coordinates: {} });
    const run = frozen('rendered', raw, source, new Map([['rendered.txt', rendered], ['render-log.txt', log]])); cli(run);
    assert(readFileSync(join(run, 'corpus/sources/material.bin')).equals(source));
    writeInventory(run, (inv) => { inv.provenance.find((p) => p.type === 'supplied-rendering')!.declaration_asset_id = 'none'; });
    cli(run, 'PROVENANCE');
  }, 'PROVENANCE');
  inventoryMutation('raw declaration prevents coordinated Markdown rewrite', 'INVENTORY', (inv) => { inv.objects.find((o) => o.kind === 'caption')!.reason = 'coordinated change'; inv.objects.find((o) => o.kind === 'caption')!.state = 'degraded'; });
  inventoryMutation('renamed second representation cannot upgrade captured state', 'INVENTORY', (inv) => { inv.representations.push({ ...inv.representations[0], representation_id: 'REP-9999' }); });
  inventoryMutation('duplicate material identity fails closed', 'IDENTITY', (inv) => { inv.bindings.push({ ...inv.bindings[0] }); });
  inventoryMutation('unknown state fails closed', 'STATE', (inv) => { inv.objects[0].state = 'restored'; });
  inventoryMutation('noncanonical coordinate JSON fails closed', 'FORMAT', (inv) => { inv.objects[0].coordinates = '{ }'; });
  inventoryMutation('out-of-range row ordinal is refused', 'COORDINATE', (inv) => {
    inv.objects.find((o) => o.kind === 'row')!.coordinates = '{"index":99}';
  });
  inventoryMutation('false complete table grid is refused', 'COORDINATE', (inv) => {
    const cell = inv.objects.find((o) => o.kind === 'cell' && JSON.parse(o.binding_ids).includes('BND-0005'))!;
    inv.objects = inv.objects.filter((o) => o !== cell);
    inv.associations = inv.associations.filter((a) => a.subject_id !== cell.object_id);
  });
  inventoryMutation('AST cannot claim frozen-source byte role', 'BINDING', (inv) => { inv.bindings[0].byte_role = 'retained-asset-bytes'; });
  test('unlisted asset is refused', () => {
    const run = frozen('extra-asset'); writeFileSync(join(run, 'corpus/representation-assets/extra.bin'), 'extra'); cli(run, 'INVENTORY');
  }, 'INVENTORY');
  test('asset symlink is refused', () => {
    const run = frozen('symlink'); const ctx = readRepresentationContext(loadRun(run)), path = join(run, ctx.inventory.assets[0].locus);
    rmSync(path); symlinkSync(join(run, 'corpus/sources/material.bin'), path); cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('source hash changed after freeze is refused', () => {
    const run = frozen('source-change'); writeFileSync(join(run, 'corpus/sources/material.bin'), 'changed'); cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('changed asset bytes retain a capture-hash failure', () => {
    const run = frozen('changed-asset'), context = readRepresentationContext(loadRun(run));
    writeFileSync(join(run, context.inventory.assets[0].locus), 'changed');
    cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('frozen degraded-to-available upgrade cannot rewrite capture facts', () => {
    const run = frozen('state-upgrade');
    writeInventory(run, (inv) => { inv.representations[0].state = 'available'; inv.representations[0].reason = 'none'; }, false);
    cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('inventory seal changed after freeze is refused', () => {
    const run = frozen('seal-change'); writeInventory(run, (inv) => { inv.representations[0].reason += '; changed'; }, false); cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  inventoryMutation('missing header association cannot be silently omitted', 'ASSOCIATION', (inv) => { inv.associations.shift(); });
  inventoryMutation('nonexistent caption fails', 'ASSOCIATION', (inv) => {
    inv.associations.find((a) => a.kind === 'caption-for')!.target_ids = '["OBJ-9999"]';
  });
  inventoryMutation('asset length disagreement fails', 'CAPTURE_HASH', (inv) => { inv.assets[0].byte_length = String(Number(inv.assets[0].byte_length) + 1); });
  inventoryMutation('dropped ordered fragment with retained object hash is refused', 'BINDING', (inv) => {
    const object = inv.objects.find((o) => o.kind === 'formal')!;
    object.binding_ids = '[]';
  });
  inventoryMutation('BND cannot split a multibyte glyph', 'BINDING', (inv) => {
    const b = inv.bindings.at(-1)!;
    b.end_byte = String(source.length - 2);
    const bytes = source.subarray(Number(b.start_byte), Number(b.end_byte));
    b.fragment_hash = materialHash(bytes); b.exact_bytes_base64 = bytes.toString('base64');
  });
  inventoryMutation('noncanonical base64 fails', 'BINDING', (inv) => { inv.bindings[0].exact_bytes_base64 += '\n'; });
  test('raw descriptor exponent integer fails even with renewed asset hash', () => {
    const run = frozen('numeric-lexeme'), ctx = readRepresentationContext(loadRun(run));
    const raw = ctx.carriers.get('AST-0001')!.bytes.toString('utf8');
    assert(raw.includes('"index":1'));
    replaceAsset(run, 'AST-0001', Buffer.from(raw.replace('"index":1', '"index":1e0')));
    cli(run, 'FORMAT');
  }, 'FORMAT');
  test('duplicate raw descriptor member fails', () => {
    const run = frozen('duplicate-member'), ctx = readRepresentationContext(loadRun(run));
    const raw = ctx.carriers.get('AST-0001')!.bytes.toString('utf8');
    replaceAsset(run, 'AST-0001', Buffer.from(raw.replace('"source_path":', '"source_path":"ignored","source_path":')));
    cli(run, 'FORMAT');
  }, 'FORMAT');
  test('unknown raw descriptor member fails', () => {
    const run = frozen('unknown-member'), context = readRepresentationContext(loadRun(run));
    const raw = JSON.parse(context.carriers.get('AST-0001')!.bytes.toString('utf8'));
    raw.inferred_structure = true; replaceAsset(run, 'AST-0001', Buffer.from(JSON.stringify(raw)));
    cli(run, 'FORMAT');
  }, 'FORMAT');
  test('ID map must remain bijective', () => {
    const run = frozen('map-bijection'), ctx = readRepresentationContext(loadRun(run));
    const map = JSON.parse(ctx.carriers.get('AST-0002')!.bytes.toString('utf8'));
    const keys = Object.keys(map.id_map).filter((k) => k.startsWith('OBJ-'));
    map.id_map[keys[1]] = map.id_map[keys[0]];
    replaceAsset(run, 'AST-0002', Buffer.from(JSON.stringify(map)));
    cli(run, 'INVENTORY');
  }, 'INVENTORY');
  test('overlapping supplied region boxes remain structural PASS', () => {
    const raw = descriptor();
    const base = { kind: 'page', parent_id: 'OBJ-0001', state: 'available', reason: 'none', provenance_id: 'RPR-0001',
      binding_ids: ['BND-0002'], content_hash: raw.objects.find((o) => JSON.stringify(o.binding_ids) === '["BND-0002"]')!.content_hash };
    raw.objects.push({ object_id: 'OBJ-0300', ...base, coordinates: { index: 1, label: null, space: { unit: 'pixel', width: 100, height: 100, origin: 'top-left' } } });
    for (const [id, x] of [['OBJ-0301', 0], ['OBJ-0302', 10]] as const)
      raw.objects.push({ object_id: id, ...base, kind: 'region', parent_id: 'OBJ-0300',
        coordinates: { page_id: 'OBJ-0300', box: { x0: x, y0: 0, x1: 80, y1: 80 } } });
    cli(frozen('overlapping-regions', raw));
    const run = frozen('out-of-range-region', raw);
    writeInventory(run, (inv) => {
      const region = inv.objects.find((o) => o.kind === 'region')!;
      const c = JSON.parse(region.coordinates); c.box.x1 = 101; region.coordinates = JSON.stringify(c);
    });
    cli(run, 'COORDINATE');
  }, 'COORDINATE');
  test('reserved material injected into predecessor format is refused', () => {
    const run = copyPositive('legacy-injection'); const p = join(run, 'run-manifest.md');
    writeFileSync(p, readFileSync(p, 'utf8').replace('1.6.0-provisional', '1.5.0-provisional')); cli(run, 'FORMAT');
  }, 'FORMAT');
  test('unknown format is refused', () => {
    const run = copyPositive('unknown-format'); const p = join(run, 'run-manifest.md');
    writeFileSync(p, readFileSync(p, 'utf8').replace('1.6.0-provisional', '99.0.0-provisional')); cli(run, 'FORMAT');
  }, 'FORMAT');
  test('frozen inventory omission is refused', () => {
    const run = frozen('missing-inventory'); rmSync(join(run, REPRESENTATION_PATH)); cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('frozen inventory hash omission is refused', () => {
    const run = frozen('missing-inventory-hash'), path = join(run, 'run-manifest.md');
    writeFileSync(path, readFileSync(path, 'utf8').replace(/^.*representation_inventory_hash:.*\n/gmu, ''));
    cli(run, 'CAPTURE_HASH');
  }, 'CAPTURE_HASH');
  test('missing canonical receipt is refused', () => {
    const run = copyPositive('missing-receipt'); const ctx = readRepresentationContext(loadRun(run)); ctx.uses.shift(); sealedUses(run, ctx.uses); cli(run, 'USE_CLOSURE');
  }, 'USE_CLOSURE');
  useMutation('changed retained subject digest is refused', 'USE_CLOSURE', (r) => { r.review_subject_digest = 'sha256:' + '0'.repeat(64); });
  for (const kind of ['CC', 'REL']) test(`missing ${kind} receipt is refused`, () => {
    const run = copyPositive(`missing-${kind}`), context = readRepresentationContext(loadRun(run));
    const index = context.uses.findIndex((r) => r.subject_kind === kind); assert(index >= 0);
    context.uses.splice(index, 1); sealedUses(run, context.uses); cli(run, 'USE_CLOSURE');
  }, 'USE_CLOSURE');
  test('lost basis packet is refused even with a renewed subject digest', () => {
    const run = copyPositive('lost-basis'), model = loadRun(run), context = readRepresentationContext(model);
    const row = context.uses.find((r) => r.subject_kind === 'CC' && JSON.parse(r.basis_packet_ids).length > 1)!;
    row.basis_packet_ids = JSON.stringify(JSON.parse(row.basis_packet_ids).slice(1));
    row.review_subject_digest = representationUseDigest(model, context, row);
    sealedUses(run, context.uses); cli(run, 'USE_CLOSURE');
  }, 'USE_CLOSURE');
  for (const [path, before, after] of [
    ['ledgers/claim-inventory.md', 'Original claim later split', 'Changed normalized claim'],
    ['ledgers/relations.md', 'invocation:s4-relations-01', 'invocation:changed-producer'],
  ]) test(`changed ${path} invalidates the retained material subject`, () => {
    const run = copyPositive('changed-subject'), original = readFileSync(join(run, path), 'utf8');
    assert(original.includes(before)); writeFileSync(join(run, path), original.replace(before, after)); cli(run, 'USE_CLOSURE');
  }, 'USE_CLOSURE');
  test('C1 use seal prevents changed receipt bytes', () => {
    const run = copyPositive('use-seal'); writeFileSync(join(run, REPRESENTATION_USE_PATH), readFileSync(join(run, REPRESENTATION_USE_PATH), 'utf8') + '\n'); cli(run, 'FROZEN_WRITE');
  }, 'FROZEN_WRITE');
  test('later stages cannot erase the C1 marker and material seal together', () => {
    const run = copyPositive('erased-c1'), path = join(run, 'run-log.md');
    writeFileSync(path, readFileSync(path, 'utf8').replace(/^closure_phase: S4-C1-relations-closed\r?\n/gmu, '')
      .replace(/^representation_use_closure_hash:.*\r?\n/gmu, ''));
    cli(run, 'FROZEN_WRITE');
  }, 'FROZEN_WRITE');
  test('use ledger rejects invalid UTF-8 even under an updated seal', () => {
    const run = copyPositive('uses-utf8');
    const bytes = Buffer.concat([readFileSync(join(run, REPRESENTATION_USE_PATH)), Buffer.from([255])]);
    writeFileSync(join(run, REPRESENTATION_USE_PATH), bytes);
    const log = join(run, 'run-log.md');
    writeFileSync(log, readFileSync(log, 'utf8').replace(/representation_use_closure_hash: sha256:[0-9a-f]{64}/u,
      `representation_use_closure_hash: ${materialHash(bytes)}`));
    cli(run, 'FORMAT');
  }, 'FORMAT');
  test('section 17 limitation table cannot disappear', () => {
    const run = copyPositive('limitation-summary'); const p = join(run, 'precis.md');
    writeFileSync(p, readFileSync(p, 'utf8').replace(materialTableMarkdown(LIMITATION_HEADERS, []), '')); cli(run, 'USE_CLOSURE');
  }, 'USE_CLOSURE');
  test('1.6 source-walk review digest binds inventory identity', () => {
    const run = copyPositive('walk-basis'), model = loadRun(run), review = model.sourceWalk.gapReviews[0].values;
    const before = sourceWalkReviewBasisDigest(model, review.sourceId, review.reviewBasisCursorId);
    model.manifest!.bullets.fields.set('representation inventory hash', 'sha256:' + '0'.repeat(64));
    assert.notEqual(sourceWalkReviewBasisDigest(model, review.sourceId, review.reviewBasisCursorId), before);
  });
  test('real K2.14 rejects a prior gap-review digest after inventory identity changes', () => {
    const run = copyPositive('stale-gap-review'), path = join(run, 'ledgers/source-walk.md'), oldWalk = readFileSync(path);
    writeInventory(run, (inv) => { inv.representations[0].origin_kind = 'original-capture'; });
    refreshFixtureBindings(run); writeFileSync(path, oldWalk);
    cli(run, 'current primary review basis', 'K2.14');
  });
  test('CANNOT_DETERMINE requires reason and limitation without gold', () => {
    assert.throws(() => validateMaterialUseInput({ requirements: [{ object_id: 'OBJ-0001', feature: 'formal-structure', binding_ids: [] }],
      use_state: 'CANNOT_DETERMINE', fidelity_claim: 'none', limitation_refs: [], reason: 'none' }));
  });
  test('Core preserves verifier and canonical material-use spellings', () => {
    assert.equal(materialReviewUseState({ verdict: 'cannot-determine' }), 'CANNOT_DETERMINE');
    assert.equal(materialReviewUseState({ verdict: 'upheld' }), 'usable');
    assert.equal(materialReviewUseState({ verdict: 'refuted' }), null);
    assert.throws(() => materialReviewUseState({ verdict: 'PASS' }), /STATE/u);
  });
  console.log(`Representation structural cases: ${reports.length}/${reports.length} PASS; semantic adequacy is not certified.`);
} finally {
  if (process.env.ALEPH_REPRESENTATION_REPORT) writeFileSync(process.env.ALEPH_REPRESENTATION_REPORT, JSON.stringify(reports, null, 2) + '\n');
  rmSync(TEMP, { recursive: true, force: true });
}
