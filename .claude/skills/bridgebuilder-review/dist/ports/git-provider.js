/** Typed error thrown by git provider adapters for structured classification. */
export class GitProviderError extends Error {
    code;
    constructor(code, message) {
        super(message);
        this.name = "GitProviderError";
        this.code = code;
    }
}
//# sourceMappingURL=git-provider.js.map