import type { ILLMProvider } from "../ports/llm-provider.js";
/**
 * Configuration for creating a provider adapter.
 *
 * cycle-103 note: `apiKey` and `costRates` are accepted for backward
 * compatibility with existing callers (multi-model-pipeline.ts threads
 * env-derived keys) but are NOT used by the delegate. Credentials cross to
 * the child cheval process via env inheritance (AC-1.8 (a)); cost tracking
 * lives entirely on the cheval side via model-config.yaml cost tables.
 */
export interface AdapterConfig {
    provider: string;
    modelId: string;
    apiKey: string;
    timeoutMs?: number;
    costRates?: {
        input: number;
        output: number;
    };
    /** Optional: pin a cheval agent binding. Defaults to "flatline-reviewer". */
    agent?: string;
    /** Optional: AC-1.2 — passthrough to `python3 cheval.py --mock-fixture-dir`. */
    mockFixtureDir?: string;
}
/**
 * Create an LLM provider adapter for the given configuration.
 *
 * Post-cycle-103: always returns a `ChevalDelegateAdapter`. The `provider`
 * argument is no longer dispatched against a registry; cheval's own resolver
 * (loa_cheval/routing/resolver.py) maps the modelId to a provider via
 * model-config.yaml. Unknown providers / model IDs surface as cheval exit 2
 * (INVALID_REQUEST) at call time, not at factory time.
 */
export declare function createAdapter(config: AdapterConfig): ILLMProvider;
//# sourceMappingURL=adapter-factory.d.ts.map