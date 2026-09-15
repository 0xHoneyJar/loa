import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { hasRunCapability, SUPPORTED_RUN_FORMAT_VERSIONS, type RunModel } from './run-model.ts';
import type { ResultCollector } from './results.ts';
import { SEMANTIC_PATH, validateSemanticRun } from './semantic-review.ts';

export function semanticArtifactsPresent(model: RunModel): boolean {
  return [SEMANTIC_PATH, 'verification/harness/semantic-subjects', 'verification/harness/semantic-results',
    'verification/harness/semantic-assignments', 'verification/harness/semantic-stage-seals']
    .some((path) => existsSync(join(model.runDir, path)))
    || [model.manifest, model.runLog].some((doc) => doc && /^\s*(?:-\s*)?(?:semantic_review_closure_hash|semantic_review_seal_ref|semantic_stage):/mu.test(doc.text));
}
export function runK2Semantics(results: ResultCollector, model: RunModel): void {
  const version = model.manifest?.runFormatVersion || '', active = hasRunCapability(version, 'semantic-unit-review');
  if (!active && !semanticArtifactsPresent(model) && (!version || (SUPPORTED_RUN_FORMAT_VERSIONS as readonly string[]).includes(version))) return;
  results.run('K2.19', 'semantic subject and review accounting (STRUCTURAL ONLY)', () => {
    if (!active) throw new Error(`SEM_COMPATIBILITY ${version}: canonical semantic artifacts require semantic-unit-review`);
    const report = validateSemanticRun(model);
    return `structure only; subjects=${report.subjects}; assignments=${report.assignments}; results=${report.results}; pending=${JSON.stringify(report.pending)}; execution=${JSON.stringify(report.executions)}; no semantic correctness or production execution inferred`;
  });
}
