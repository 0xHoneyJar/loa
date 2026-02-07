/**
 * Bridge module barrel export.
 * Per SDD Section 4.4.
 */

export {
  BeadsBridge,
  createBeadsBridge,
} from "./beads-bridge.js";
export type {
  Bead,
  HealthCheckResult,
  BeadsBridgeConfig,
  BrExecutor,
} from "./beads-bridge.js";
