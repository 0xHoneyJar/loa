/**
 * Beads Bridge — typed TypeScript wrapper for br CLI.
 *
 * Uses execFile with argument arrays (never exec with string interpolation).
 * Write operations serialized via promise queue. Per SDD Section 4.4.
 */
import { execFile, execFileSync } from "node:child_process";
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface Bead {
  id: string;
  title: string;
  type: string;
  status: "open" | "closed" | "in_progress";
  priority: number;
  labels: string[];
  description?: string;
  created_at: string;
  updated_at: string;
  parent_id?: string;
  depends_on?: string[];
  blocked_by?: string[];
}

export interface HealthCheckResult {
  healthy: boolean;
  version?: string;
  reason?: string;
}

export interface BeadsBridgeConfig {
  /** Path to br binary. Default: "br" */
  brPath?: string;
  /** Max output buffer in bytes. Default: 1MB */
  maxBuffer?: number;
  /** Command timeout in ms. Default: 30000 */
  timeoutMs?: number;
}

// ── Input Validation (IMP-002) ───────────────────────

const ID_REGEX = /^[a-zA-Z0-9_-]{1,128}$/;
const VALID_STATUSES = new Set(["open", "closed", "in_progress"]);
const MAX_REASON_LENGTH = 1024;
const PRIORITY_MIN = 0;
const PRIORITY_MAX = 10;

function validateId(id: string): void {
  if (!ID_REGEX.test(id)) {
    throw new LoaLibError(
      `Invalid bead ID: "${id}" — must match ${ID_REGEX}`,
      "BRG_005",
      false,
    );
  }
}

function validateStatus(status: string): void {
  if (!VALID_STATUSES.has(status)) {
    throw new LoaLibError(
      `Invalid status: "${status}" — must be one of: ${[...VALID_STATUSES].join(", ")}`,
      "BRG_005",
      false,
    );
  }
}

function validatePriority(priority: number): void {
  if (!Number.isInteger(priority) || priority < PRIORITY_MIN || priority > PRIORITY_MAX) {
    throw new LoaLibError(
      `Invalid priority: ${priority} — must be integer ${PRIORITY_MIN}-${PRIORITY_MAX}`,
      "BRG_005",
      false,
    );
  }
}

function validateReason(reason: string): void {
  if (reason.length > MAX_REASON_LENGTH) {
    throw new LoaLibError(
      `Reason too long: ${reason.length} chars (max: ${MAX_REASON_LENGTH})`,
      "BRG_005",
      false,
    );
  }
}

// ── ExecFile wrapper ─────────────────────────────────

interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

/** Injectable executor for testing */
export interface BrExecutor {
  exec(args: string[], opts: { maxBuffer: number; timeout: number }): Promise<ExecResult>;
}

function createDefaultExecutor(brPath: string): BrExecutor {
  return {
    exec(args, opts) {
      return new Promise((resolve, reject) => {
        execFile(
          brPath,
          args,
          { maxBuffer: opts.maxBuffer, timeout: opts.timeout },
          (error, stdout, stderr) => {
            if (error) {
              const code = (error as NodeJS.ErrnoException).code;
              const exitCode = error.code !== undefined && typeof error.code === "number"
                ? error.code
                : (error as { status?: number }).status ?? 1;

              if (code === "ENOENT") {
                resolve({ stdout: "", stderr: "", exitCode: 127 });
              } else if (error.killed) {
                resolve({ stdout: stdout ?? "", stderr: stderr ?? "", exitCode: -1 });
              } else {
                resolve({ stdout: stdout ?? "", stderr: stderr ?? "", exitCode });
              }
            } else {
              resolve({ stdout: stdout ?? "", stderr: stderr ?? "", exitCode: 0 });
            }
          },
        );
      });
    },
  };
}

// ── Error Mapping ────────────────────────────────────

function mapExitCode(exitCode: number, stderr: string): LoaLibError {
  switch (exitCode) {
    case 127:
      return new LoaLibError("br binary not found on PATH", "BRG_001", false);
    case -1:
      return new LoaLibError("br command timed out", "BRG_002", true);
    default:
      return new LoaLibError(
        `br command failed (exit ${exitCode}): ${stderr.trim().slice(0, 200)}`,
        "BRG_004",
        true,
      );
  }
}

function parseJson<T>(stdout: string, validator: (v: unknown) => v is T): T {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new LoaLibError(
      `Failed to parse br JSON output: ${stdout.slice(0, 200)}`,
      "BRG_003",
      false,
    );
  }
  if (!validator(parsed)) {
    throw new LoaLibError(
      `br JSON output failed runtime validation: ${stdout.slice(0, 200)}`,
      "BRG_003",
      false,
    );
  }
  return parsed;
}

// ── Runtime Validators (SEC-AUDIT TS-CRIT-02) ────────

function isBeadArray(v: unknown): v is Bead[] {
  if (!Array.isArray(v)) return false;
  return v.every(isBead);
}

function isBead(v: unknown): v is Bead {
  if (typeof v !== "object" || v === null) return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.id === "string" &&
    typeof o.title === "string" &&
    typeof o.type === "string" &&
    typeof o.status === "string" &&
    VALID_STATUSES.has(o.status as string) &&
    typeof o.priority === "number" &&
    Array.isArray(o.labels) &&
    typeof o.created_at === "string" &&
    typeof o.updated_at === "string"
  );
}

// ── Resolve absolute binary path (SEC-AUDIT TS-CRIT-03) ──

function resolveAbsoluteBrPath(brPath: string): string {
  // Already absolute — use as-is
  if (brPath.startsWith("/")) return brPath;

  try {
    const resolved = execFileSync("which", [brPath], { timeout: 5000 }).toString().trim();
    if (resolved) return resolved;
  } catch {
    // which failed — fall through to use bare name (ENOENT will be caught at runtime)
  }
  return brPath;
}

// ── BeadsBridge ──────────────────────────────────────

export class BeadsBridge {
  private readonly executor: BrExecutor;
  private readonly maxBuffer: number;
  private readonly timeoutMs: number;
  /** Single-writer promise queue for write ops */
  private writeQueue: Promise<void> = Promise.resolve();

  constructor(config?: BeadsBridgeConfig, executor?: BrExecutor) {
    const brPath = resolveAbsoluteBrPath(config?.brPath ?? "br");
    this.executor = executor ?? createDefaultExecutor(brPath);
    this.maxBuffer = config?.maxBuffer ?? 1024 * 1024;
    this.timeoutMs = config?.timeoutMs ?? 30_000;
  }

  // ── Read Operations ────────────────────────────────

  async healthCheck(): Promise<HealthCheckResult> {
    try {
      const result = await this.run(["--version"]);
      if (result.exitCode === 127) {
        return { healthy: false, reason: "binary_not_found" };
      }
      if (result.exitCode !== 0) {
        return { healthy: false, reason: `exit_code_${result.exitCode}` };
      }
      const version = result.stdout.trim();
      return { healthy: true, version };
    } catch {
      return { healthy: false, reason: "unknown_error" };
    }
  }

  async list(): Promise<Bead[]> {
    const result = await this.runOrThrow(["list", "--json"]);
    return parseJson<Bead[]>(result.stdout, isBeadArray);
  }

  async ready(): Promise<Bead[]> {
    const result = await this.runOrThrow(["ready", "--json"]);
    return parseJson<Bead[]>(result.stdout, isBeadArray);
  }

  async get(id: string): Promise<Bead> {
    validateId(id);
    const result = await this.runOrThrow(["show", id, "--json"]);
    return parseJson<Bead>(result.stdout, isBead);
  }

  // ── Write Operations (serialized) ──────────────────

  async update(id: string, opts: { status?: string; priority?: number; reason?: string }): Promise<void> {
    validateId(id);
    const args = ["update", id];
    if (opts.status !== undefined) {
      validateStatus(opts.status);
      args.push("--status", opts.status);
    }
    if (opts.priority !== undefined) {
      validatePriority(opts.priority);
      args.push("--priority", String(opts.priority));
    }
    if (opts.reason !== undefined) {
      validateReason(opts.reason);
      args.push("--reason", opts.reason);
    }
    await this.serializedWrite(() => this.runOrThrow(args));
  }

  async close(id: string, reason?: string): Promise<void> {
    validateId(id);
    const args = ["close", id];
    if (reason !== undefined) {
      validateReason(reason);
      args.push("--reason", reason);
    }
    await this.serializedWrite(() => this.runOrThrow(args));
  }

  async sync(): Promise<void> {
    await this.serializedWrite(() => this.runOrThrow(["sync"]));
  }

  // ── Private ────────────────────────────────────────

  private async run(args: string[]): Promise<ExecResult> {
    return this.executor.exec(args, {
      maxBuffer: this.maxBuffer,
      timeout: this.timeoutMs,
    });
  }

  private async runOrThrow(args: string[]): Promise<ExecResult> {
    const result = await this.run(args);
    if (result.exitCode !== 0) {
      throw mapExitCode(result.exitCode, result.stderr);
    }
    return result;
  }

  private serializedWrite<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      this.writeQueue = this.writeQueue
        .then(() => fn())
        .then(resolve, reject);
    });
  }
}

// ── Factory ──────────────────────────────────────────

export function createBeadsBridge(config?: BeadsBridgeConfig, executor?: BrExecutor): BeadsBridge {
  return new BeadsBridge(config, executor);
}
