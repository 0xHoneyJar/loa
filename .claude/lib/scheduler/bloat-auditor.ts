/**
 * Bloat Auditor — resource proliferation guard.
 *
 * Detects excessive crons, orphan state files, script proliferation.
 * Per SDD Section 4.3.7.
 */

// ── Types ────────────────────────────────────────────

export type WarningType = "excessive_crons" | "orphan_state" | "script_proliferation";

export interface BloatWarning {
  type: WarningType;
  message: string;
  count: number;
  threshold: number;
}

export interface BloatReport {
  clean: boolean;
  warnings: BloatWarning[];
}

export interface BloatThresholds {
  maxCrons?: number;
  maxStateFiles?: number;
  maxScripts?: number;
}

export interface FileSystemScanner {
  countFiles(path: string, pattern?: string): number | Promise<number>;
}

export interface BloatAuditorConfig {
  thresholds?: BloatThresholds;
  scanner: FileSystemScanner;
  paths: {
    crons?: string;
    state?: string;
    scripts?: string;
  };
}

// ── BloatAuditor ─────────────────────────────────────

export class BloatAuditor {
  private readonly maxCrons: number;
  private readonly maxStateFiles: number;
  private readonly maxScripts: number;
  private readonly scanner: FileSystemScanner;
  private readonly paths: { crons?: string; state?: string; scripts?: string };

  constructor(config: BloatAuditorConfig) {
    this.maxCrons = config.thresholds?.maxCrons ?? 20;
    this.maxStateFiles = config.thresholds?.maxStateFiles ?? 50;
    this.maxScripts = config.thresholds?.maxScripts ?? 100;
    this.scanner = config.scanner;
    this.paths = config.paths;
  }

  async audit(): Promise<BloatReport> {
    const warnings: BloatWarning[] = [];

    if (this.paths.crons) {
      const count = await this.scanner.countFiles(this.paths.crons);
      if (count > this.maxCrons) {
        warnings.push({
          type: "excessive_crons",
          message: `Found ${count} cron entries (threshold: ${this.maxCrons})`,
          count,
          threshold: this.maxCrons,
        });
      }
    }

    if (this.paths.state) {
      const count = await this.scanner.countFiles(this.paths.state);
      if (count > this.maxStateFiles) {
        warnings.push({
          type: "orphan_state",
          message: `Found ${count} state files (threshold: ${this.maxStateFiles})`,
          count,
          threshold: this.maxStateFiles,
        });
      }
    }

    if (this.paths.scripts) {
      const count = await this.scanner.countFiles(this.paths.scripts);
      if (count > this.maxScripts) {
        warnings.push({
          type: "script_proliferation",
          message: `Found ${count} scripts (threshold: ${this.maxScripts})`,
          count,
          threshold: this.maxScripts,
        });
      }
    }

    return {
      clean: warnings.length === 0,
      warnings,
    };
  }
}

// ── Factory ──────────────────────────────────────────

export function createBloatAuditor(config: BloatAuditorConfig): BloatAuditor {
  return new BloatAuditor(config);
}
