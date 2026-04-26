/**
 * 8 structural depth elements for Bridgebuilder review quality assessment.
 * Each element represents a dimension of review depth beyond basic code analysis.
 */
export interface DepthElements {
    /** FAANG/industry system parallels (e.g., "Netflix's Zuul", "Google's Borg") */
    faangParallel: boolean;
    /** Metaphors or analogies that illuminate concepts */
    metaphor: boolean;
    /** Teachable moments extending beyond the specific fix */
    teachableMoment: boolean;
    /** Technical history or evolution context */
    techHistory: boolean;
    /** Revenue, business, or organizational impact analysis */
    businessImpact: boolean;
    /** Social or team dynamics implications */
    socialDynamics: boolean;
    /** Cross-repository pattern connections */
    crossRepoConnection: boolean;
    /** Frame-questioning or reframing of the problem */
    frameQuestion: boolean;
}
export interface DepthResult {
    elements: DepthElements;
    score: number;
    total: number;
    passed: boolean;
    minThreshold: number;
}
export interface DepthCheckerConfig {
    minElements?: number;
    logPath?: string;
}
/**
 * Check structural depth of a review against the 8-element checklist.
 */
export declare function checkDepth(reviewContent: string, config?: DepthCheckerConfig): DepthResult;
/**
 * Log a depth check result as a JSONL entry.
 */
export declare function logDepthResult(result: DepthResult, meta: {
    runId: string;
    model: string;
    provider?: string;
}, logPath?: string): Promise<void>;
//# sourceMappingURL=depth-checker.d.ts.map