import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";
export interface OpenAIAdapterOptions {
    costRates?: {
        input: number;
        output: number;
    };
}
export declare class OpenAIAdapter implements ILLMProvider {
    private readonly apiKey;
    private readonly model;
    private readonly timeoutMs;
    private readonly costInput;
    private readonly costOutput;
    constructor(apiKey: string, model: string, timeoutMs?: number, options?: OpenAIAdapterOptions);
    generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
//# sourceMappingURL=openai.d.ts.map