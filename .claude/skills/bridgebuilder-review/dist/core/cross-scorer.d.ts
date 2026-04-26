/**
 * CrossScorer — pairwise cross-model scoring with bounded output.
 *
 * Performs N*(N-1) pairwise comparisons between model findings to identify
 * agreements and disagreements. Bounded to 4K output per comparison.
 */
import type { ModelFindings } from "./scoring.js";
export interface PairwiseComparison {
    model_a: string;
    model_b: string;
    agreements: Array<{
        finding_a_id: string;
        finding_b_id: string;
        similarity: number;
        severity_match: boolean;
    }>;
    disagreements: Array<{
        finding_id: string;
        model: string;
        severity: string;
        reason: string;
    }>;
}
export interface CrossScoringResult {
    comparisons: PairwiseComparison[];
    agreement_rate: number;
    total_pairs: number;
}
/**
 * Perform pairwise cross-scoring between model results.
 *
 * @param modelResults - Findings from each model
 * @param options - Optional configuration
 * @returns Cross-scoring result with pairwise comparisons
 */
export declare function crossScore(modelResults: ModelFindings[], options?: {
    maxRetries?: number;
}): CrossScoringResult;
//# sourceMappingURL=cross-scorer.d.ts.map