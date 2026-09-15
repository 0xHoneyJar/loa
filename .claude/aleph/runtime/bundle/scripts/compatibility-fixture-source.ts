import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
const expect: (condition: unknown, message: string) => asserts condition = assert;

/** Exercise predecessor mechanics using a separate synthetic compatibility bundle. */
export function predecessorSource(repository: string, root: string, version = '1.5.0-provisional'): string {
  const target = join(root, `source-${version}`); mkdirSync(target);
  const inventory = spawnSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: repository, encoding: 'utf8' });
  expect(inventory.status === 0, 'cannot inventory compatibility source');
  for (const path of new Set(inventory.stdout.split('\0').filter(Boolean))) {
    mkdirSync(dirname(join(target, path)), { recursive: true });
    copyFileSync(join(repository, path), join(target, path));
  }
  for (const path of ['core.manifest.json', 'adapters/loa/adapter.manifest.json', 'adapters/hermes/adapter.manifest.json', 'adapter-protocol/adapter.schema.json']) {
    writeFileSync(join(target, path), readFileSync(join(target, path), 'utf8').replaceAll('1.7.0-provisional', version));
  }
  const prompts = join(target, 'docs/architecture/prompts/workers-intake-extraction.md');
  const strip = (value: unknown): unknown => Array.isArray(value) ? value.map(strip)
    : value && typeof value === 'object' && 'contract_format' in value && 'shape' in value ? strip(value.shape)
    : value && typeof value === 'object' ? Object.fromEntries(Object.entries(value).filter(([k]) => !(version === '1.5.0-provisional'
      ? ['material_use', 'material_findings', 'semantic_units'] : ['semantic_units']).includes(k)).map(([k,v]) => [k,strip(v)])) : value;
  writeFileSync(prompts, readFileSync(prompts, 'utf8').replace(/```json\n([\s\S]*?)\n```/gu, (_all, json: string) => '```json\n' + JSON.stringify(strip(JSON.parse(json)), null, 2) + '\n```'));
  for (const args of [['init', '-q'], ['add', '--all'], ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Synthetic predecessor compatibility source']]) {
    const result = spawnSync('git', args, { cwd: target, encoding: 'utf8' });
    expect(result.status === 0, `compatibility repository preparation failed: ${result.stderr}`);
  }
  return target;
}
