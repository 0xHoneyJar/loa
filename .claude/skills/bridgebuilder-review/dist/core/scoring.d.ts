/**
 * BridgebuilderScorer — dual-track consensus scoring for multi-model reviews.
 *
 * Track 1 (Convergence): Classifies findings as HIGH_CONSENSUS, DISPUTED, LOW_VALUE, or BLOCKER.
 * Track 2 (Diversity): Deduplicates findings across models while preserving unique perspectives.
 */
export type ConsensusClassification = "HIGH_CONSENSUS" | "DISPUTED" | "LOW_VALUE" | "BLOCKER";
export interface ScoringThresholds {
    high_consensus: number;
    disputed_delta: number;
    low_value: number;
    blocker: number;
}
export interface ScoredFinding {
    /** The canonical finding (from the highest-scoring model). */
    finding: ModelFinding;
    /** Consensus classification. */
    classification: ConsensusClassification;
    /** Models that produced a similar finding. */
    agreeing_models: string[];
    /** Average severity score across models. */
    avg_score: number;
    /** Delta between highest and lowest model scores. */
    score_delta: number;
    /** Whether this finding was unique to one model (diversity track). */
    unique: boolean;
}
export interface ModelFinding {
    id: string;
    title: string;
    severity: string;
    category: string;
    file?: string;
    description: string;
    suggestion?: string;
    confidence?: number;
    faang_parallel?: string;
    metaphor?: string;
    teachable_moment?: string;
    connection?: string;
    [key: string]: unknown;
}
export interface ModelFindings {
    provider: string;
    model: string;
    findings: ModelFinding[];
}
export interface ScoringResult {
    /** Track 1: convergence-classified findings. */
    convergence: ScoredFinding[];
    /** Track 2: unique perspectives preserved from individual models. */
    diversity: ModelFinding[];
    /** Summary statistics. */
    stats: {
        total_findings: number;
        high_consensus: number;
        disputed: number;
        low_value: number;
        blocker: number;
        unique: number;
        models_contributing: number;
    };
}
/**
 * Score findings from multiple models using dual-track consensus.
 */
export declare function scoreFindings(modelResults: ModelFindings[], thresholds?: Partial<ScoringThresholds>): ScoringResult;
/**
 * Levenshtein similarity (0.0 = completely different, 1.0 = identical).
 * Optimized for short-to-medium strings (< 500 chars).
 */
export declare function levenshteinSimilarity(a: string, b: string): number;
//# sourceMappingURL=scoring.d.ts.map