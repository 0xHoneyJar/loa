export interface ReviewVerdict {
    verdict: "REQUEST_CHANGES" | "APPROVE" | "COMMENT" | "UNKNOWN";
    highestSeverity: string | null;
    mergeBlocked: boolean;
    /** Why the merge is blocked when it is not the verdict itself (r251-4 S1: a host fault — the Loa config unreadable). */
    mergeBlockedReason?: string;
}
/** Review transport success and GitHub COMMENTED state are not merge clearance. */
export declare function summarizeReviewVerdict(content: string, findings?: ReadonlyArray<{
    severity: string;
}>): ReviewVerdict;
//# sourceMappingURL=review-verdict.d.ts.map