import type { ReviewResult } from "../core/types.js";

export interface IContextStore {
  load(): Promise<void>;
  getLastHash(owner: string, repo: string, prNumber: number): Promise<string | null>;
  setLastHash(owner: string, repo: string, prNumber: number, hash: string): Promise<void>;
  claimReview(owner: string, repo: string, prNumber: number): Promise<boolean>;
  finalizeReview(
    owner: string,
    repo: string,
    prNumber: number,
    result: ReviewResult,
  ): Promise<void>;
}
