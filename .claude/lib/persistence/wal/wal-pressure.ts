/**
 * WAL Disk Pressure Monitoring.
 *
 * Two-threshold hysteresis:
 *   normal → warning (at warningBytes) → critical (at criticalBytes)
 *
 * Warning triggers early compaction; critical rejects new writes.
 */

export type DiskPressureStatus = "normal" | "warning" | "critical";

export interface DiskPressureConfig {
  /** Bytes threshold for warning level. Default: 100MB */
  warningBytes: number;
  /** Bytes threshold for critical level. Default: 150MB */
  criticalBytes: number;
}

const DEFAULT_PRESSURE_CONFIG: DiskPressureConfig = {
  warningBytes: 100 * 1024 * 1024, // 100MB
  criticalBytes: 150 * 1024 * 1024, // 150MB
};

/**
 * Evaluate disk pressure level from total WAL size.
 */
export function evaluateDiskPressure(
  totalBytes: number,
  config?: Partial<DiskPressureConfig>,
): DiskPressureStatus {
  const c = { ...DEFAULT_PRESSURE_CONFIG, ...config };

  if (totalBytes >= c.criticalBytes) return "critical";
  if (totalBytes >= c.warningBytes) return "warning";
  return "normal";
}
