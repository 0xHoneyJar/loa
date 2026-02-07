/**
 * Sync module barrel export.
 * Per SDD Section 4.5.
 */

// ── Recovery Cascade ────────────────────────────────
export {
  RecoveryCascade,
  createRecoveryCascade,
} from "./recovery-cascade.js";
export type {
  IRecoverySource,
  RecoveryAttempt,
  RecoveryResult,
  RecoveryCascadeConfig,
} from "./recovery-cascade.js";

// ── Object Store Sync ───────────────────────────────
export {
  InMemoryObjectStore,
  createInMemoryObjectStore,
  ObjectStoreSync,
  createObjectStoreSync,
} from "./object-store-sync.js";
export type {
  IObjectStore,
  SyncCounts,
} from "./object-store-sync.js";

// ── WAL Pruner ──────────────────────────────────────
export {
  WALPruner,
  createWALPruner,
} from "./wal-pruner.js";
export type {
  WALEntry,
  WALPruneTarget,
  PruneResult,
  WALPrunerConfig,
} from "./wal-pruner.js";

// ── Graceful Shutdown ───────────────────────────────
export {
  GracefulShutdown,
  createGracefulShutdown,
} from "./graceful-shutdown.js";
export type {
  GracefulShutdownConfig,
} from "./graceful-shutdown.js";
