import type { IContextStore } from "../ports/context-store.js";
import type { ReviewItem, ReviewResult } from "./types.js";
/**
 * Manages review state: change detection via hash comparison,
 * claim/finalize lifecycle delegation to IContextStore.
 *
 * BridgebuilderContext owns the change detection logic.
 * IContextStore only provides persistence (getLastHash/setLastHash).
 *
 * With NoOpContextStore: getLastHash returns null (always changed),
 * so local mode relies on GitHub marker check in ReviewPipeline.
 */
export declare class BridgebuilderContext {
    private readonly store;
    constructor(store: IContextStore);
    /** Load persisted state from the store. */
    load(): Promise<void>;
    /**
     * Check if a review item has changed since last review.
     * Compares item.hash (canonical: headSha + sorted filenames) with stored hash.
     * Returns true if changed or never reviewed.
     */
    hasChanged(item: ReviewItem): Promise<boolean>;
    /**
     * Claim a review slot. Delegates to IContextStore.
     * NoOpContextStore always returns true.
     * R2ContextStore uses CAS for distributed locking.
     */
    claimReview(item: ReviewItem): Promise<boolean>;
    /**
     * Finalize a review: persist hash, headSha, and result.
     * Stores the current hash so hasChanged() returns false next time.
     * Stores headSha for incremental review on next run (V3-1).
     */
    finalizeReview(item: ReviewItem, result: ReviewResult): Promise<void>;
    /**
     * Get the head SHA from the last completed review (V3-1 incremental).
     * Returns null if never reviewed or not persisted.
     */
    getLastReviewedSha(item: ReviewItem): Promise<string | null>;
}
//# sourceMappingURL=context.d.ts.map