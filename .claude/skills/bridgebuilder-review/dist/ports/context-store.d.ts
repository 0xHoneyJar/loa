import type { ReviewResult } from "../core/types.js";
export interface IContextStore {
    load(): Promise<void>;
    getLastHash(owner: string, repo: string, prNumber: number): Promise<string | null>;
    setLastHash(owner: string, repo: string, prNumber: number, hash: string): Promise<void>;
    claimReview(owner: string, repo: string, prNumber: number): Promise<boolean>;
    finalizeReview(owner: string, repo: string, prNumber: number, result: ReviewResult): Promise<void>;
    /** Get the head SHA from the last completed review (V3-1 incremental). */
    getLastReviewedSha(owner: string, repo: string, prNumber: number): Promise<string | null>;
    /** Persist the head SHA after a review completes (V3-1 incremental). */
    setLastReviewedSha(owner: string, repo: string, prNumber: number, sha: string): Promise<void>;
}
//# sourceMappingURL=context-store.d.ts.map