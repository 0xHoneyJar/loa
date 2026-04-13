import type { ILLMProvider } from "../ports/llm-provider.js";
import { AnthropicAdapter } from "./anthropic.js";

/**
 * Configuration for creating a provider adapter.
 */
export interface AdapterConfig {
  provider: string;
  modelId: string;
  apiKey: string;
  timeoutMs?: number;
}

/**
 * Registry of provider adapter constructors.
 * Adding a new provider = adding one entry here + the adapter file.
 */
const ADAPTER_REGISTRY: Record<
  string,
  (apiKey: string, modelId: string, timeoutMs: number) => ILLMProvider
> = {
  anthropic: (apiKey, modelId, timeoutMs) =>
    new AnthropicAdapter(apiKey, modelId, timeoutMs),
  // openai and google adapters will be registered in Sprint 2
  // openai: (apiKey, modelId, timeoutMs) => new OpenAIAdapter(apiKey, modelId, timeoutMs),
  // google: (apiKey, modelId, timeoutMs) => new GoogleAdapter(apiKey, modelId, timeoutMs),
};

/**
 * Create an LLM provider adapter for the given configuration.
 * Extensible: adding a new provider requires only a new adapter class
 * and a single entry in ADAPTER_REGISTRY.
 *
 * @throws Error if provider is unknown.
 */
export function createAdapter(config: AdapterConfig): ILLMProvider {
  const factory = ADAPTER_REGISTRY[config.provider];
  if (!factory) {
    const available = Object.keys(ADAPTER_REGISTRY).join(", ");
    throw new Error(
      `Unknown provider: "${config.provider}". Available providers: ${available}`,
    );
  }
  return factory(config.apiKey, config.modelId, config.timeoutMs ?? 120_000);
}

/**
 * Register a new provider adapter at runtime.
 * Used by Sprint 2 to add OpenAI and Google adapters.
 */
export function registerAdapter(
  provider: string,
  factory: (apiKey: string, modelId: string, timeoutMs: number) => ILLMProvider,
): void {
  ADAPTER_REGISTRY[provider] = factory;
}

/**
 * Get list of registered provider names.
 */
export function getRegisteredProviders(): string[] {
  return Object.keys(ADAPTER_REGISTRY);
}
