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
}

/** Typed error codes for LLM provider operations. */
export type LLMProviderErrorCode = "TOKEN_LIMIT" | "RATE_LIMITED" | "INVALID_REQUEST" | "NETWORK";

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
