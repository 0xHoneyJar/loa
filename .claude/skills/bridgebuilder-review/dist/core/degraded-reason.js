/**
 * cycle-133 C-1/C-2 (sdd.md § 1.4, FR-1/FR-2): the fixed enumeration of reasons a completed review is DEGRADED. A run
 * carrying any of them exits `bridgebuilder.exit_on_degraded` (default 3) and its summary JSON carries `degraded: true`
 * and `degraded_reason`. Fetch-side reasons (the first five) always come with `mergeBlockedReason: incomplete_coverage`.
 */
export const DEGRADED_REASONS = [
    "files_payload_oversize",
    "files_list_truncated",
    "page_incomplete",
    "patch_fetch_rate_limited",
    "pr_head_moved",
    // cycle-135 C-2 (review round 1): the PR base's `.reviewignore` could not be read, so the checkout's copy (which the
    // PR head controls) governed the exclusions — the review is complete but its exclusion set is untrusted.
    "reviewignore_unavailable",
    "incomplete_coverage",
    "enrichment_guard_rejected",
    "writer_not_eligible",
    "verdict_conflict",
];
/** The enumeration as a value (`DegradedReason.pr_head_moved`), for callers that prefer member access. */
export const DegradedReason = Object.freeze(Object.fromEntries(DEGRADED_REASONS.map((r) => [r, r])));
/** The fetch-side reasons: the review's file coverage is incomplete, so the merge is blocked as incomplete_coverage. */
export const FETCH_DEGRADED_REASONS = new Set([
    "files_payload_oversize", "files_list_truncated", "page_incomplete", "patch_fetch_rate_limited", "pr_head_moved",
    "reviewignore_unavailable",
]);
export function isDegradedReason(value) {
    return typeof value === "string" && DEGRADED_REASONS.includes(value);
}
/** The primary reason of a set: the first in enumeration order (deterministic for the summary JSON). */
export function primaryDegradedReason(reasons) {
    return DEGRADED_REASONS.find((r) => reasons.includes(r));
}
/** The distinct reasons of a list in enumeration order. */
export function orderDegradedReasons(reasons) {
    return DEGRADED_REASONS.filter((r) => reasons.includes(r));
}
//# sourceMappingURL=degraded-reason.js.map