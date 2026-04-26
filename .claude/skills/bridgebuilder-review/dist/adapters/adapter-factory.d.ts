import type { ILLMProvider } from "../ports/llm-provider.js";
/**
 * Configuration for creating a provider adapter.
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
}
/**
 * Create an LLM provider adapter for the given configuration.
 * Extensible: adding a new provider requires only a new adapter class
 * and a single entry in ADAPTER_REGISTRY.
 *
 * @throws Error if provider is unknown.
 */
export declare function createAdapter(config: AdapterConfig): ILLMProvider;
/**
 * Register a new provider adapter at runtime.
 * Used by Sprint 2 to add OpenAI and Google adapters.
 */
export declare function registerAdapter(provider: string, factory: (apiKey: string, modelId: string, timeoutMs: number) => ILLMProvider): void;
/**
 * Get list of registered provider names.
 */
export declare function getRegisteredProviders(): string[];
//# sourceMappingURL=adapter-factory.d.ts.map