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
export class BridgebuilderContext {
  constructor(private readonly store: IContextStore) {}

  /** Load persisted state from the store. */
  async load(): Promise<void> {
    await this.store.load();
  }

  /**
   * Check if a review item has changed since last review.
   * Compares item.hash (canonical: headSha + sorted filenames) with stored hash.
   * Returns true if changed or never reviewed.
   */
  async hasChanged(item: ReviewItem): Promise<boolean> {
    const lastHash = await this.store.getLastHash(
      item.owner,
      item.repo,
      item.pr.number,
    );
    if (lastHash == null) return true;
    return lastHash !== item.hash;
  }

  /**
   * Claim a review slot. Delegates to IContextStore.
   * NoOpContextStore always returns true.
   * R2ContextStore uses CAS for distributed locking.
   */
  async claimReview(item: ReviewItem): Promise<boolean> {
    return this.store.claimReview(item.owner, item.repo, item.pr.number);
  }

  /**
   * Finalize a review: persist hash, headSha, and result.
   * Stores the current hash so hasChanged() returns false next time.
   * Stores headSha for incremental review on next run (V3-1).
   */
  async finalizeReview(
    item: ReviewItem,
    result: ReviewResult,
  ): Promise<void> {
    await this.store.setLastHash(
      item.owner,
      item.repo,
      item.pr.number,
      item.hash,
    );
    await this.store.setLastReviewedSha(
      item.owner,
      item.repo,
      item.pr.number,
      item.pr.headSha,
    );
    await this.store.finalizeReview(
      item.owner,
      item.repo,
      item.pr.number,
      result,
    );
  }

  /**
   * Get the head SHA from the last completed review (V3-1 incremental).
   * Returns null if never reviewed or not persisted.
   */
  async getLastReviewedSha(item: ReviewItem): Promise<string | null> {
    return this.store.getLastReviewedSha(
      item.owner,
      item.repo,
      item.pr.number,
    );
  }
}
