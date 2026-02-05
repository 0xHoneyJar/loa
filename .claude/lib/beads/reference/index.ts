/**
 * Beads Reference Implementations
 *
 * Simple reference implementations of the abstract interfaces.
 * These are for demonstration, testing, and as starting points
 * for custom implementations.
 *
 * **NOT RECOMMENDED** for production without review.
 *
 * @module beads/reference
 * @version 1.0.0
 */

export { FileWALAdapter, createFileWAL, type FileWALConfig } from "./file-wal";
export {
  IntervalScheduler,
  createIntervalScheduler,
  type IntervalSchedulerConfig,
} from "./interval-scheduler";
export {
  JsonStateStore,
  createJsonStateStore,
  type JsonStateStoreConfig,
} from "./json-state-store";
