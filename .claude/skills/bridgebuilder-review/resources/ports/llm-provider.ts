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

export interface ILLMProvider {
  generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
