/**
 * Scheduler Module — barrel export.
 *
 * Re-exports all public types, classes, and factory functions
 * from scheduler submodules.
 */

// Core scheduler
export {
  type TaskState,
  type ScheduledTaskConfig,
  type TaskStatus,
  type SchedulerConfig,
  Scheduler,
  createScheduler,
} from "./scheduler.js";

// Notification sink
export {
  type INotificationChannel,
  type WebhookSinkConfig,
  type NotificationAdapter,
  WebhookSink,
  SlackAdapter,
  DiscordAdapter,
  createWebhookSink,
} from "./notification-sink.js";

// Health aggregator
export {
  type HealthState,
  type SubsystemHealth,
  type HealthReport,
  type IHealthReporter,
  HealthAggregator,
  createHealthAggregator,
} from "./health-aggregator.js";

// Timeout enforcer
export {
  type TimeoutEnforcerConfig,
  type RunOptions,
  TimeoutEnforcer,
  createTimeoutEnforcer,
} from "./timeout-enforcer.js";

// MECE validator
export {
  type TaskDefinition,
  type Overlap,
  type MECEReport,
  validateMECE,
} from "./mece-validator.js";

// Bloat auditor
export {
  type WarningType,
  type BloatWarning,
  type BloatReport,
  type BloatThresholds,
  type FileSystemScanner,
  type BloatAuditorConfig,
  BloatAuditor,
  createBloatAuditor,
} from "./bloat-auditor.js";
