import type { IOutputSanitizer, SanitizationResult } from "../ports/output-sanitizer.js";
export declare class PatternSanitizer implements IOutputSanitizer {
    private readonly extraPatterns;
    constructor(extraPatterns?: RegExp[]);
    sanitize(content: string): SanitizationResult;
}
//# sourceMappingURL=sanitizer.d.ts.map