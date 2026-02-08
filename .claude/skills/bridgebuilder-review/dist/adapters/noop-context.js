// Decision: NoOp over file-based or DB-backed context store.
// Local CLI mode runs as one-shot (invoke, review, exit). Persistent state
// across runs is handled by the GitHub review marker (<!-- bridgebuilder-review: sha -->)
// which acts as an idempotency key. A file-based store would add filesystem
// coupling and stale-state bugs for zero benefit in the single-operator case.
// When multi-operator or scheduled runs are needed, swap to a real IContextStore
// (e.g. SQLite or Redis) behind the same port interface.
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