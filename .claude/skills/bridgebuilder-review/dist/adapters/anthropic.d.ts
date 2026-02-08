import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";
export declare class AnthropicAdapter implements ILLMProvider {
    private readonly apiKey;
    private readonly model;
    private readonly timeoutMs;
    constructor(apiKey: string, model: string, timeoutMs?: number);
    generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
//# sourceMappingURL=anthropic.d.ts.map