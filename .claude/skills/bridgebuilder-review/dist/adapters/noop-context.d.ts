import type { IContextStore } from "../ports/context-store.js";
import type { ReviewResult } from "../core/types.js";
export declare class NoOpContextStore implements IContextStore {
    load(): Promise<void>;
    getLastHash(_owner: string, _repo: string, _prNumber: number): Promise<string | null>;
    setLastHash(_owner: string, _repo: string, _prNumber: number, _hash: string): Promise<void>;
    claimReview(_owner: string, _repo: string, _prNumber: number): Promise<boolean>;
    finalizeReview(_owner: string, _repo: string, _prNumber: number, _result: ReviewResult): Promise<void>;
    getLastReviewedSha(_owner: string, _repo: string, _prNumber: number): Promise<string | null>;
    setLastReviewedSha(_owner: string, _repo: string, _prNumber: number, _sha: string): Promise<void>;
}
//# sourceMappingURL=noop-context.d.ts.map