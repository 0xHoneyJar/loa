import { existsSync } from 'node:fs';
import { join } from 'node:path';
import type { ResultCollector } from './results.ts';
import { SUPPORTED_RUN_FORMAT_VERSIONS, usesFormalLayoutBindings, type RunModel } from './run-model.ts';
import { REPRESENTATION_ASSET_PATH, REPRESENTATION_PATH, REPRESENTATION_USE_PATH, validateRepresentationRun } from './source-representation.ts';

export function runK2Representations(results: ResultCollector, model: RunModel): void {
  const version = model.manifest?.runFormatVersion || '';
  const present = [REPRESENTATION_PATH, REPRESENTATION_ASSET_PATH, REPRESENTATION_USE_PATH].some((path) => existsSync(join(model.runDir, path)))
    || [...model.documents.values()].some((doc) => doc && !doc.relativePath.startsWith('corpus/sources/')
      && /(?:source_representation_format|representation_use_format|representation_inventory_hash|representation_use_closure_hash):/u.test(doc.text));
  // Preserve predecessor reports byte-for-byte when no reserved material is injected.
  if (!usesFormalLayoutBindings(version) && !present
    && (!version || (SUPPORTED_RUN_FORMAT_VERSIONS as readonly string[]).includes(version))) return;
  results.run('K2.18', 'source representation bindings (STRUCTURAL ONLY)', (fail) => {
    if (!usesFormalLayoutBindings(version)) {
      fail(`FORMAT run-manifest.md field run_format_version: unknown format or reserved material injected into ${version}`);
      return;
    }
    if (!present && model.manifest?.states.every((row) => ['DRAFT', 'BLOCKED'].includes(row.values.state))) return 'DRAFT capture not prepared';
    const context = validateRepresentationRun(model);
    const rows = [...context.inventory.representations, ...context.inventory.objects, ...context.inventory.associations];
    const counts = Object.fromEntries(['available', 'degraded', 'unsupported', 'indeterminate'].map((state) => [state, rows.filter((r) => r.state === state).length]));
    const limitations = rows.filter((r) => r.state !== 'available').map((r) => `${Object.values(r)[0]}:${r.state}:${r.reason}`).sort();
    const undetermined = context.uses.filter((r) => r.use_state === 'CANNOT_DETERMINE').map((r) => r.use_id).sort();
    return `declared structure only; states=${JSON.stringify(counts)}; limitations=${JSON.stringify(limitations)}; CANNOT_DETERMINE=${JSON.stringify(undetermined)}`;
  });
}
