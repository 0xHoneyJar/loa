/**
 * Memory module barrel export.
 */

// ── Quality Gates ────────────────────────────────────
export {
  temporalGate,
  speculationGate,
  instructionGate,
  confidenceGate,
  qualityGate,
  technicalGate,
  evaluateAllGates,
} from "./quality-gates.js";
export type { MemoryEntry, GateResult } from "./quality-gates.js";

// ── Context Tracker ──────────────────────────────────
export { ContextTracker, createContextTracker } from "./context-tracker.js";
export type {
  ITokenCounter,
  UsageLevel,
  ContextTrackerConfig,
} from "./context-tracker.js";

// ── Compound Learning ────────────────────────────────
export {
  CompoundLearningCycle,
  createCompoundLearningCycle,
} from "./compound-learning.js";
export type {
  Pattern,
  CompoundLearningConfig,
} from "./compound-learning.js";
