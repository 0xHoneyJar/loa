// cycle-103 Sprint 1 T1.4 — adapter-factory collapsed onto cheval delegate.
//
// The per-provider adapter registry (anthropic.ts / openai.ts / google.ts) was
// retired in cycle-103. All provider calls now flow through the cheval Python
// substrate via ChevalDelegateAdapter, so provider-side fixes ship once
// (Python) and propagate to every TypeScript consumer.
//
// Spec: grimoires/loa/cycles/cycle-103-provider-unification/sdd.md §2.1
//       (Removed in cycle-103) + sprint.md T1.4 + AC-1.1.
import { ChevalDelegateAdapter } from "./cheval-delegate.js";
const DEFAULT_TIMEOUT_MS = 120_000;
/**
 * Create an LLM provider adapter for the given configuration.
 *
 * Post-cycle-103: always returns a `ChevalDelegateAdapter`. The `provider`
 * argument is no longer dispatched against a registry; cheval's own resolver
 * (loa_cheval/routing/resolver.py) maps the modelId to a provider via
 * model-config.yaml. Unknown providers / model IDs surface as cheval exit 2
 * (INVALID_REQUEST) at call time, not at factory time.
 */
export function createAdapter(config) {
    return new ChevalDelegateAdapter({
        model: config.modelId,
        timeoutMs: config.timeoutMs ?? DEFAULT_TIMEOUT_MS,
        agent: config.agent,
        mockFixtureDir: config.mockFixtureDir,
    });
}
//# sourceMappingURL=adapter-factory.js.map