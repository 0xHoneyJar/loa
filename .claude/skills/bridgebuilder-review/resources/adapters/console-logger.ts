import type { ILogger } from "../ports/logger.js";

/** Patterns to redact from log output. */
const DEFAULT_REDACT_PATTERNS: RegExp[] = [
  /gh[ps]_[A-Za-z0-9_]{36,}/g,
  /github_pat_[A-Za-z0-9_]{22,}/g,
  /sk-ant-[A-Za-z0-9-]{20,}/g,
  /sk-[A-Za-z0-9]{20,}/g,
  /AKIA[A-Z0-9]{16}/g,
  /xox[bprs]-[A-Za-z0-9-]{10,}/g,
];

function redact(value: string, patterns: RegExp[]): string {
  let result = value;
  for (const pattern of patterns) {
    result = result.replace(
      new RegExp(pattern.source, pattern.flags),
      "[REDACTED]",
    );
  }
  return result;
}

function safeStringify(
  data: Record<string, unknown> | undefined,
  patterns: RegExp[],
): string {
  if (!data) return "";
  const raw = JSON.stringify(data);
  return redact(raw, patterns);
}

export class ConsoleLogger implements ILogger {
  private readonly patterns: RegExp[];

  constructor(extraPatterns?: RegExp[]) {
    this.patterns = [...DEFAULT_REDACT_PATTERNS, ...(extraPatterns ?? [])];
  }

  info(message: string, data?: Record<string, unknown>): void {
    this.log("info", message, data);
  }

  warn(message: string, data?: Record<string, unknown>): void {
    this.log("warn", message, data);
  }

  error(message: string, data?: Record<string, unknown>): void {
    this.log("error", message, data);
  }

  debug(message: string, data?: Record<string, unknown>): void {
    this.log("debug", message, data);
  }

  private log(
    level: string,
    message: string,
    data?: Record<string, unknown>,
  ): void {
    const entry = {
      level,
      message: redact(message, this.patterns),
      ...(data ? { data: JSON.parse(safeStringify(data, this.patterns)) } : {}),
      timestamp: new Date().toISOString(),
    };
    const out = level === "error" ? console.error : console.log;
    out(JSON.stringify(entry));
  }
}
