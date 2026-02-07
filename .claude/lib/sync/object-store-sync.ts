/**
 * Object Store Sync — IObjectStore interface + in-memory impl + push/pull.
 *
 * Per SDD Section 4.5.2. No S3 reference implementation (per GPT review).
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface IObjectStore {
  get(key: string): Promise<Buffer | null>;
  put(key: string, data: Buffer): Promise<void>;
  delete(key: string): Promise<void>;
  list(prefix?: string): Promise<string[]>;
}

export interface SyncCounts {
  pushed: number;
  pulled: number;
  deleted: number;
}

// ── In-Memory Object Store (for testing) ─────────────

export class InMemoryObjectStore implements IObjectStore {
  private readonly store = new Map<string, Buffer>();

  async get(key: string): Promise<Buffer | null> {
    return this.store.get(key) ?? null;
  }

  async put(key: string, data: Buffer): Promise<void> {
    this.store.set(key, data);
  }

  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }

  async list(prefix?: string): Promise<string[]> {
    const keys = [...this.store.keys()];
    if (!prefix) return keys;
    return keys.filter((k) => k.startsWith(prefix));
  }

  /** Test helper: number of stored objects */
  size(): number {
    return this.store.size;
  }
}

export function createInMemoryObjectStore(): InMemoryObjectStore {
  return new InMemoryObjectStore();
}

// ── Object Store Sync ────────────────────────────────

export class ObjectStoreSync {
  constructor(
    private readonly local: IObjectStore,
    private readonly remote: IObjectStore,
  ) {}

  /** Push all local keys to remote */
  async push(prefix?: string): Promise<number> {
    const keys = await this.local.list(prefix);
    let count = 0;
    for (const key of keys) {
      const data = await this.local.get(key);
      if (data !== null) {
        await this.remote.put(key, data);
        count++;
      }
    }
    return count;
  }

  /** Pull all remote keys to local */
  async pull(prefix?: string): Promise<number> {
    const keys = await this.remote.list(prefix);
    let count = 0;
    for (const key of keys) {
      const data = await this.remote.get(key);
      if (data !== null) {
        await this.local.put(key, data);
        count++;
      }
    }
    return count;
  }

  /** Bidirectional sync: push local, pull remote, return counts */
  async sync(prefix?: string): Promise<SyncCounts> {
    const pushed = await this.push(prefix);
    const pulled = await this.pull(prefix);
    return { pushed, pulled, deleted: 0 };
  }
}

export function createObjectStoreSync(
  local: IObjectStore,
  remote: IObjectStore,
): ObjectStoreSync {
  return new ObjectStoreSync(local, remote);
}
