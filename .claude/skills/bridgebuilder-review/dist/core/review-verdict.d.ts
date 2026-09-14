export interface ReviewVerdict {
    verdict: "REQUEST_CHANGES" | "APPROVE" | "COMMENT" | "UNKNOWN";
    highestSeverity: string | null;
    mergeBlocked: boolean;
}
/** Review transport success and GitHub COMMENTED state are not merge clearance. */
export declare function summarizeReviewVerdict(content: string, findings?: ReadonlyArray<{
    severity: string;
}>): ReviewVerdict;
//# sourceMappingURL=review-verdict.d.ts.map