export interface ReviewRequest {
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
}

export interface ReviewResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
  /** Provider identifier (e.g., "anthropic", "openai", "google"). Multi-model extension. */
  provider?: string;
  /** Wall-clock time for the API call in milliseconds. Multi-model extension. */
  latencyMs?: number;
  /** Estimated cost in USD for this call. Multi-model extension. */
  estimatedCostUsd?: number;
  /** Error state if the call failed but returned partial content. Multi-model extension. */
  errorState?: LLMProviderErrorCode | null;
}

/** Typed error codes for LLM provider operations. */
export type LLMProviderErrorCode =
  | "TOKEN_LIMIT"
  | "RATE_LIMITED"
  | "INVALID_REQUEST"
  | "NETWORK"
  | "TIMEOUT"
  | "AUTH_ERROR"
  | "PROVIDER_ERROR";

/** Typed error thrown by LLM provider adapters for structured classification. */
export class LLMProviderError extends Error {
  readonly code: LLMProviderErrorCode;

  constructor(code: LLMProviderErrorCode, message: string) {
    super(message);
    this.name = "LLMProviderError";
    this.code = code;
  }
}

export interface ILLMProvider {
  generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
