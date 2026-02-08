export interface SanitizationResult {
    safe: boolean;
    sanitizedContent: string;
    redactedPatterns: string[];
}
export interface IOutputSanitizer {
    sanitize(content: string): SanitizationResult;
}
//# sourceMappingURL=output-sanitizer.d.ts.map