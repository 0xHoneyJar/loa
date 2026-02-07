/**
 * Security module barrel export.
 * Per SDD Section 4.1.3.
 */

// ── PII Redactor ─────────────────────────────────────
export { PIIRedactor, createPIIRedactor } from "./pii-redactor.js";
export type {
  PIIPattern,
  PIIRedactorConfig,
  RedactionMatch,
} from "./pii-redactor.js";

// ── Audit Logger ─────────────────────────────────────
export { AuditLogger, createAuditLogger } from "./audit-logger.js";
export type { AuditEntry, AuditLoggerConfig } from "./audit-logger.js";
