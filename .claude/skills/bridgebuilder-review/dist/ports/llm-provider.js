/** Typed error thrown by LLM provider adapters for structured classification. */
export class LLMProviderError extends Error {
    code;
    constructor(code, message) {
        super(message);
        this.name = "LLMProviderError";
        this.code = code;
    }
}
//# sourceMappingURL=llm-provider.js.map