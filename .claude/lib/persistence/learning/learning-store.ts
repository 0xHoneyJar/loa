/**
 * Learning Store — portable CRUD for compound learnings.
 *
 * Extracted from deploy/loa-identity/learning-store.ts.
 * Uses constructor-injected paths (no process.env dependency).
 * WAL integration is optional for graceful degradation.
 *
 * Storage locations (relative to configured base path):
 *   - Active learnings:  {basePath}/learnings.json
 *   - Pending self-improvements: {basePath}/pending-self/
 *
 * @module .claude/lib/persistence/learning/learning-store
 */

import { randomUUID } from "crypto";
import * as fs from "fs";
import * as path from "path";

// ── Types ──────────────────────────────────────────────────

export type LearningSource = "sprint" | "error-cycle" | "retrospective";
export type LearningTarget = "loa" | "devcontainer" | "moltworker" | "openclaw";
export type LearningStatus = "pending" | "approved" | "active" | "archived";

export interface QualityGates {
  discovery_depth: number;
  reusability: number;
  trigger_clarity: number;
  verification: number;
}

export interface Learning {
  id: string;
  created: string;
  source: LearningSource;
  trigger: string;
  pattern: string;
  solution: string;
  gates: QualityGates;
  target: LearningTarget;
  status: LearningStatus;
  approved_by?: string;
  approved_at?: string;
  effectiveness?: {
    applications: number;
    successes: number;
    failures: number;
    last_applied?: string;
  };
}

export interface LearningsStore {
  version: string;
  learnings: Learning[];
}

/** Optional WAL for write-protection. */
export interface ILearningWAL {
  write(path: string, content: string): Promise<void>;
}

/** Configuration for LearningStore. */
export interface LearningStoreConfig {
  basePath: string;
  wal?: ILearningWAL;
}

// ── Quality Gate Scoring ───────────────────────────────────

export interface IQualityGateScorer {
  scoreAll(learning: Partial<Learning>): QualityGates;
  passes(learning: Partial<Learning>): boolean;
}

// UUID pattern for validating learning IDs (prevents path traversal)
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── Store Implementation ───────────────────────────────────

export class LearningStore {
  private readonly basePath: string;
  private readonly wal?: ILearningWAL;
  private readonly scorer?: IQualityGateScorer;
  /** Promise chain for serializing write operations (prevents lost updates) */
  private writeChain: Promise<void> = Promise.resolve();

  constructor(config: LearningStoreConfig, scorer?: IQualityGateScorer) {
    this.basePath = config.basePath;
    this.wal = config.wal;
    this.scorer = scorer;
  }

  private validateId(id: string): void {
    if (!UUID_PATTERN.test(id)) {
      throw new Error(`Invalid learning ID: ${id}`);
    }
  }

  private get learningsPath(): string {
    return path.join(this.basePath, "learnings.json");
  }

  private get pendingSelfDir(): string {
    return path.join(this.basePath, "pending-self");
  }

  // ── Store Operations ─────────────────────────────────────

  async loadStore(): Promise<LearningsStore> {
    try {
      const data = await fs.promises.readFile(this.learningsPath, "utf8");
      return JSON.parse(data);
    } catch {
      return { version: "1.0.0", learnings: [] };
    }
  }

  async saveStore(store: LearningsStore): Promise<void> {
    const content = JSON.stringify(store, null, 2);

    if (this.wal) {
      await this.wal.write(this.learningsPath, content);
    } else {
      await fs.promises.mkdir(path.dirname(this.learningsPath), { recursive: true });
      await fs.promises.writeFile(this.learningsPath, content);
    }
  }

  // ── CRUD ─────────────────────────────────────────────────

  async addLearning(
    learning: Omit<Learning, "id" | "created" | "gates" | "status">,
  ): Promise<Learning> {
    const id = randomUUID();
    const created = new Date().toISOString();
    const gates = this.scorer?.scoreAll(learning) ?? {
      discovery_depth: 5,
      reusability: 5,
      trigger_clarity: 5,
      verification: 5,
    };

    const newLearning: Learning = {
      ...learning,
      id,
      created,
      gates,
      status: "pending",
    };

    // Check quality gates
    if (this.scorer && !this.scorer.passes(newLearning)) {
      return newLearning; // Discarded
    }

    // Serialize writes to prevent lost updates
    await this.serializedWrite(async () => {
      // Self-improvement requires human approval
      if (learning.target === "loa") {
        await this.savePendingSelf(newLearning);
      } else {
        newLearning.status = "active";
        const store = await this.loadStore();
        store.learnings.push(newLearning);
        await this.saveStore(store);
      }
    });

    return newLearning;
  }

  async getLearning(id: string): Promise<Learning | null> {
    this.validateId(id);
    const store = await this.loadStore();
    const learning = store.learnings.find((l) => l.id === id);
    if (learning) return learning;

    // Check pending-self
    const pendingPath = path.join(this.pendingSelfDir, `${id}.json`);
    try {
      const data = await fs.promises.readFile(pendingPath, "utf8");
      return JSON.parse(data);
    } catch {
      return null;
    }
  }

  async getLearnings(status?: LearningStatus): Promise<Learning[]> {
    const store = await this.loadStore();
    return status ? store.learnings.filter((l) => l.status === status) : store.learnings;
  }

  async getLearningsByTarget(target: LearningTarget): Promise<Learning[]> {
    const store = await this.loadStore();
    return store.learnings.filter((l) => l.target === target);
  }

  async getPendingLearnings(): Promise<Learning[]> {
    const pending: Learning[] = [];

    try {
      await fs.promises.mkdir(this.pendingSelfDir, { recursive: true });
      const files = await fs.promises.readdir(this.pendingSelfDir);

      for (const file of files) {
        if (!file.endsWith(".json")) continue;
        try {
          const data = await fs.promises.readFile(path.join(this.pendingSelfDir, file), "utf8");
          pending.push(JSON.parse(data));
        } catch {
          // Skip invalid files
        }
      }
    } catch {
      // Directory doesn't exist yet
    }

    return pending;
  }

  async updateLearningStatus(
    id: string,
    status: LearningStatus,
    approvedBy?: string,
  ): Promise<Learning | null> {
    this.validateId(id);

    return this.serializedWrite(async () => {
      // Try pending-self first (for approvals)
      const pendingPath = path.join(this.pendingSelfDir, `${id}.json`);

      try {
        const data = await fs.promises.readFile(pendingPath, "utf8");
        const learning: Learning = JSON.parse(data);

        learning.status = status;
        if (status === "approved" || status === "active") {
          learning.approved_by = approvedBy;
          learning.approved_at = new Date().toISOString();
          learning.status = "active";

          const store = await this.loadStore();
          store.learnings.push(learning);
          await this.saveStore(store);
          await fs.promises.unlink(pendingPath);

          return learning;
        } else if (status === "archived") {
          await fs.promises.unlink(pendingPath);
          return learning;
        }
      } catch {
        // Not in pending-self
      }

      // Update in active store
      const store = await this.loadStore();
      const index = store.learnings.findIndex((l) => l.id === id);
      if (index === -1) return null;

      store.learnings[index].status = status;
      if (approvedBy) {
        store.learnings[index].approved_by = approvedBy;
        store.learnings[index].approved_at = new Date().toISOString();
      }

      await this.saveStore(store);
      return store.learnings[index];
    });
  }

  async recordApplication(id: string, success: boolean): Promise<Learning | null> {
    this.validateId(id);

    return this.serializedWrite(async () => {
      const store = await this.loadStore();
      const index = store.learnings.findIndex((l) => l.id === id);
      if (index === -1) return null;

      const learning = store.learnings[index];

      if (!learning.effectiveness) {
        learning.effectiveness = {
          applications: 0,
          successes: 0,
          failures: 0,
        };
      }

      learning.effectiveness.applications++;
      if (success) {
        learning.effectiveness.successes++;
      } else {
        learning.effectiveness.failures++;
      }
      learning.effectiveness.last_applied = new Date().toISOString();

      await this.saveStore(store);
      return learning;
    });
  }

  // ── Query Helpers ────────────────────────────────────────

  async findMatchingLearnings(context: string): Promise<Learning[]> {
    const store = await this.loadStore();
    const active = store.learnings.filter((l) => l.status === "active");

    const contextLower = context.toLowerCase();
    return active.filter((l) => {
      const words = [
        ...l.trigger.toLowerCase().split(/\s+/),
        ...l.pattern.toLowerCase().split(/\s+/),
      ];
      const matchCount = words.filter(
        (word) => word.length > 3 && contextLower.includes(word),
      ).length;
      return matchCount >= 2;
    });
  }

  async getStats(): Promise<{
    total: number;
    byStatus: Record<LearningStatus, number>;
    byTarget: Record<LearningTarget, number>;
    pendingSelf: number;
  }> {
    const store = await this.loadStore();
    const pending = await this.getPendingLearnings();

    const byStatus: Record<string, number> = {
      pending: 0,
      approved: 0,
      active: 0,
      archived: 0,
    };
    const byTarget: Record<string, number> = {
      loa: 0,
      devcontainer: 0,
      moltworker: 0,
      openclaw: 0,
    };

    for (const l of store.learnings) {
      byStatus[l.status]++;
      byTarget[l.target]++;
    }

    return {
      total: store.learnings.length,
      byStatus: byStatus as Record<LearningStatus, number>,
      byTarget: byTarget as Record<LearningTarget, number>,
      pendingSelf: pending.length,
    };
  }

  // ── Private ──────────────────────────────────────────────

  /** Serialize write operations to prevent concurrent read-modify-write races. */
  private serializedWrite<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.writeChain.then(fn);
    this.writeChain = next.then(
      () => {},
      () => {},
    ); // Keep chain alive on error
    return next;
  }

  private async savePendingSelf(learning: Learning): Promise<void> {
    await fs.promises.mkdir(this.pendingSelfDir, { recursive: true });
    const filePath = path.join(this.pendingSelfDir, `${learning.id}.json`);
    await fs.promises.writeFile(filePath, JSON.stringify(learning, null, 2));
  }
}
