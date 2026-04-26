import { AnthropicAdapter } from "./anthropic.js";
import { OpenAIAdapter } from "./openai.js";
import { GoogleAdapter } from "./google.js";
/**
 * Registry of provider adapter constructors.
 * Adding a new provider = adding one entry here + the adapter file.
 */
const ADAPTER_REGISTRY = {
    anthropic: (apiKey, modelId, timeoutMs) => new AnthropicAdapter(apiKey, modelId, timeoutMs),
    openai: (apiKey, modelId, timeoutMs, costRates) => new OpenAIAdapter(apiKey, modelId, timeoutMs, costRates ? { costRates } : undefined),
    google: (apiKey, modelId, timeoutMs, costRates) => new GoogleAdapter(apiKey, modelId, timeoutMs, costRates ? { costRates } : undefined),
};
/**
 * Create an LLM provider adapter for the given configuration.
 * Extensible: adding a new provider requires only a new adapter class
 * and a single entry in ADAPTER_REGISTRY.
 *
 * @throws Error if provider is unknown.
 */
export function createAdapter(config) {
    const factory = ADAPTER_REGISTRY[config.provider];
    if (!factory) {
        const available = Object.keys(ADAPTER_REGISTRY).join(", ");
        throw new Error(`Unknown provider: "${config.provider}". Available providers: ${available}`);
    }
    return factory(config.apiKey, config.modelId, config.timeoutMs ?? 120_000, config.costRates);
}
/**
 * Register a new provider adapter at runtime.
 * Used by Sprint 2 to add OpenAI and Google adapters.
 */
export function registerAdapter(provider, factory) {
    ADAPTER_REGISTRY[provider] = factory;
}
/**
 * Get list of registered provider names.
 */
export function getRegisteredProviders() {
    return Object.keys(ADAPTER_REGISTRY);
}
//# sourceMappingURL=adapter-factory.js.map