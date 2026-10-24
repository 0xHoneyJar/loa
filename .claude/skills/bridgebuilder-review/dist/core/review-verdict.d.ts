import { type DegradedReason } from "./degraded-reason.js";
export interface ReviewVerdict {
    verdict: "REQUEST_CHANGES" | "APPROVE" | "COMMENT" | "UNKNOWN";
    highestSeverity: string | null;
    mergeBlocked: boolean;
    /** Why the merge is blocked when it is not the verdict itself (r251-4 S1: a host fault — the Loa config unreadable). */
    mergeBlockedReason?: string;
    /** cycle-133 C-1/C-2: the review completed degraded (the run exits `bridgebuilder.exit_on_degraded`). */
    degraded?: boolean;
    /** cycle-133: the primary degraded reason (first in enumeration order). */
    degradedReason?: DegradedReason;
    degradedReasons?: DegradedReason[];
}
export interface VerdictOptions {
    /** cycle-133 C-1/C-2: degradations already established (coverage, guard, writer eligibility). */
    degradedReasons?: ReadonlyArray<DegradedReason>;
}
/**
 * Review transport success and GitHub COMMENTED state are not merge clearance.
 *
 * cycle-133 C-2 decision table (sdd.md § 1.4, FR-2, D-1.2 DEC-0840), applied in order:
 *  (1) any finding with `blocking: true` or severity CRITICAL/BLOCKER/HIGH → REQUEST_CHANGES;
 *  (2) a guard rejection, incomplete coverage or a fetch-side degradation → UNKNOWN, degraded, merge blocked with the
 *      reason (`incomplete_coverage` for every fetch-side reason);
 *  (5) two blocks, a malformed block or a block verdict contradicting (1) → `verdict_conflict`, UNKNOWN, merge blocked
 *      (under (1) the verdict stays REQUEST_CHANGES and the conflict is still recorded as a degradation);
 *  (3) exactly one valid consensus block carrying a `verdict` → that verdict (COMMENT and APPROVE clear the merge);
 *  (4) otherwise the prose rule (an explicit single verdict line; APPROVE alone clears the merge).
 * `writer_not_eligible` is a degradation that does not change the verdict: the un-enriched consensus is authoritative.
 */
export declare function summarizeReviewVerdict(content: string, findings?: ReadonlyArray<{
    severity: string;
    blocking?: unknown;
}>, options?: VerdictOptions): ReviewVerdict;
//# sourceMappingURL=review-verdict.d.ts.map