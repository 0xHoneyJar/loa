import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";
export interface GoogleAdapterOptions {
    costRates?: {
        input: number;
        output: number;
    };
}
export declare class GoogleAdapter implements ILLMProvider {
    private readonly apiKey;
    private readonly model;
    private readonly timeoutMs;
    private readonly costInput;
    private readonly costOutput;
    constructor(apiKey: string, model: string, timeoutMs?: number, options?: GoogleAdapterOptions);
    generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
//# sourceMappingURL=google.d.ts.map