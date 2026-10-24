/**
 * cycle-133 C-1/C-2 (sdd.md § 1.4, FR-1/FR-2): the fixed enumeration of reasons a completed review is DEGRADED. A run
 * carrying any of them exits `bridgebuilder.exit_on_degraded` (default 3) and its summary JSON carries `degraded: true`
 * and `degraded_reason`. Fetch-side reasons (the first five) always come with `mergeBlockedReason: incomplete_coverage`.
 */
export declare const DEGRADED_REASONS: readonly ["files_payload_oversize", "files_list_truncated", "page_incomplete", "patch_fetch_rate_limited", "pr_head_moved", "incomplete_coverage", "enrichment_guard_rejected", "writer_not_eligible", "verdict_conflict"];
export type DegradedReason = typeof DEGRADED_REASONS[number];
/** The enumeration as a value (`DegradedReason.pr_head_moved`), for callers that prefer member access. */
export declare const DegradedReason: {
    readonly [K in DegradedReason]: K;
};
/** The fetch-side reasons: the review's file coverage is incomplete, so the merge is blocked as incomplete_coverage. */
export declare const FETCH_DEGRADED_REASONS: ReadonlySet<DegradedReason>;
export declare function isDegradedReason(value: unknown): value is DegradedReason;
/** The primary reason of a set: the first in enumeration order (deterministic for the summary JSON). */
export declare function primaryDegradedReason(reasons: ReadonlyArray<DegradedReason>): DegradedReason | undefined;
/** The distinct reasons of a list in enumeration order. */
export declare function orderDegradedReasons(reasons: ReadonlyArray<DegradedReason>): DegradedReason[];
//# sourceMappingURL=degraded-reason.d.ts.map