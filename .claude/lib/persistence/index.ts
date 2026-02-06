/**
 * Loa Persistence Framework
 *
 * Portable persistence patterns extracted from deploy/loa-identity/.
 * Framework-grade library with no container dependencies.
 */

// ── Types ────────────────────────────────────────────────────
export {
  PersistenceError,
  type PersistenceErrorCode,
  type RetryConfig,
  type DiskPressureLevel,
  type StateChangeCallback,
  type EventCallback,
} from "./types.js";

// ── Circuit Breaker ──────────────────────────────────────────
export {
  CircuitBreaker,
  type CircuitBreakerState,
  type CircuitBreakerConfig,
  type CircuitBreakerStateChangeCallback,
} from "./circuit-breaker.js";

// ── WAL ──────────────────────────────────────────────────────
export { WALManager, createWALManager, type WALManagerConfig } from "./wal/wal-manager.js";
export {
  type WALEntry,
  type WALOperation,
  type WALSegment,
  type WALCheckpoint,
  generateEntryId,
  isLegacyUUID,
  verifyEntry,
} from "./wal/wal-entry.js";
export { compactEntries } from "./wal/wal-compaction.js";
export { evaluateDiskPressure, type DiskPressureStatus } from "./wal/wal-pressure.js";

// ── Checkpoint ───────────────────────────────────────────────
export {
  CheckpointProtocol,
  type CheckpointProtocolConfig,
} from "./checkpoint/checkpoint-protocol.js";
export {
  type CheckpointManifest,
  type CheckpointFileEntry,
  type WriteIntent,
  createManifest,
  verifyManifest,
} from "./checkpoint/checkpoint-manifest.js";
export { type ICheckpointStorage, MountCheckpointStorage } from "./checkpoint/storage-mount.js";

// ── Recovery ─────────────────────────────────────────────────
export {
  RecoveryEngine,
  type RecoveryState,
  type RecoveryEngineConfig,
} from "./recovery/recovery-engine.js";
export { type IRecoverySource } from "./recovery/recovery-source.js";
export { MountRecoverySource } from "./recovery/sources/mount-source.js";
export { GitRecoverySource, type GitRestoreClient } from "./recovery/sources/git-source.js";
export { TemplateRecoverySource } from "./recovery/sources/template-source.js";
export {
  ManifestSigner,
  generateKeyPair,
  createManifestSigner,
  type SignedManifest,
} from "./recovery/manifest-signer.js";

// ── Beads Bridge ─────────────────────────────────────────────
export {
  BeadsWALAdapter,
  type IBeadsWAL,
  type IBeadsWALEntry,
  type BeadWALEntry,
  type BeadOperation,
  type BeadsWALConfig,
} from "./beads/beads-wal-adapter.js";
export {
  BeadsRecoveryHandler,
  type RecoveryResult as BeadsRecoveryResult,
  type BeadsRecoveryConfig,
  type IShellExecutor,
} from "./beads/beads-recovery.js";

// ── Learning ─────────────────────────────────────────────────
export {
  LearningStore,
  type Learning,
  type LearningsStore,
  type LearningSource,
  type LearningTarget,
  type LearningStatus,
  type QualityGates,
  type ILearningWAL,
  type LearningStoreConfig,
  type IQualityGateScorer,
} from "./learning/learning-store.js";
export {
  scoreAllGates,
  passesQualityGates,
  scoreDiscoveryDepth,
  scoreReusability,
  scoreTriggerClarity,
  scoreVerification,
  DefaultQualityGateScorer,
  GATE_THRESHOLDS,
  MINIMUM_TOTAL_SCORE,
} from "./learning/quality-gates.js";

// ── Identity ─────────────────────────────────────────────────
export {
  IdentityLoader,
  createIdentityLoader,
  type IdentityDocument,
  type Principle,
  type Boundary,
  type IdentityLoaderConfig,
} from "./identity/identity-loader.js";
export {
  FileWatcher,
  type FileWatcherConfig,
  type FileChangeCallback,
} from "./identity/file-watcher.js";
