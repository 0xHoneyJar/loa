import type { IContextStore } from "../ports/context-store.js";
import type { ReviewResult } from "../core/types.js";

export class NoOpContextStore implements IContextStore {
  async load(): Promise<void> {
    // No-op: local mode has no persistent state
  }

  async getLastHash(
    _owner: string,
    _repo: string,
    _prNumber: number,
  ): Promise<string | null> {
    // Always null: forces change detection to fall through to GitHub marker check
    return null;
  }

  async setLastHash(
    _owner: string,
    _repo: string,
    _prNumber: number,
    _hash: string,
  ): Promise<void> {
    // No-op: local mode does not persist hashes
  }

  async claimReview(
    _owner: string,
    _repo: string,
    _prNumber: number,
  ): Promise<boolean> {
    // Always succeeds: no contention in local one-shot mode
    return true;
  }

  async finalizeReview(
    _owner: string,
    _repo: string,
    _prNumber: number,
    _result: ReviewResult,
  ): Promise<void> {
    // No-op: local mode does not persist review records
  }
}
