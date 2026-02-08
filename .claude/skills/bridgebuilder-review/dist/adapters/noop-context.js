export class NoOpContextStore {
    async load() {
        // No-op: local mode has no persistent state
    }
    async getLastHash(_owner, _repo, _prNumber) {
        // Always null: forces change detection to fall through to GitHub marker check
        return null;
    }
    async setLastHash(_owner, _repo, _prNumber, _hash) {
        // No-op: local mode does not persist hashes
    }
    async claimReview(_owner, _repo, _prNumber) {
        // Always succeeds: no contention in local one-shot mode
        return true;
    }
    async finalizeReview(_owner, _repo, _prNumber, _result) {
        // No-op: local mode does not persist review records
    }
}
//# sourceMappingURL=noop-context.js.map