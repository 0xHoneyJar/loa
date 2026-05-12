// cycle-103 Sprint 1 T1.2 — ChevalDelegateAdapter.
//
// BB delegates LLM-API calls to the cheval Python substrate. Replaces the
// per-provider TS adapters (anthropic.ts / openai.ts / google.ts) so that
// provider-side fixes ship once (Python) and propagate to every TS consumer.
//
// Spec: grimoires/loa/cycles/cycle-103-provider-unification/sdd.md §1.4.1, §5.3
// Sprint: grimoires/loa/cycles/cycle-103-provider-unification/sprint.md T1.2
//
// Mode: spawn-only. T1.1 benchmark (worst p95=126ms) put daemon-mode out of
// scope for Sprint 1; the `mode` option is reserved for cycle-104+.

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { LLMProviderError } from "../ports/llm-provider.js";
import type {
  ILLMProvider,
  LLMProviderErrorCode,
  ReviewRequest,
  ReviewResponse,
} from "../ports/llm-provider.js";

const DEFAULT_TIMEOUT_MS = 120_000;
const SIGKILL_GRACE_MS = 5_000;
const DEFAULT_AGENT = "reviewing-code";

const CHEVAL_SCRIPT_REL = ".claude/adapters/cheval.py";

export interface ChevalDelegateOptions {
  /** Provider:model-id string passed to cheval `--model`. */
  model: string;
  /** Wall-clock timeout for the entire spawn. SIGTERM at timeout, SIGKILL at timeout+5s. */
  timeoutMs?: number;
  /** Sprint 1 AC-1.2 — pass-through for `--mock-fixture-dir`. T1.5 wires the flag inside cheval. */
  mockFixtureDir?: string;
  /** Reserved for cycle-104+ daemon-mode. Currently only "spawn" is honored. */
  mode?: "spawn" | "daemon";
  /** Cheval agent binding name (e.g., "reviewing-code"). T1.4 will pass per-provider names. */
  agent?: string;
  /** Override for the cheval.py script path. Tests pass a fixture path; production resolves from repo root. */
  chevalScript?: string;
  /** Override for the python executable. Defaults to `python3`. */
  pythonBin?: string;
  /** Override for child-process spawn (test hook). Defaults to Node's `child_process.spawn`. */
  spawnFn?: typeof spawn;
}

/** Parsed JSON from cheval stdout when --output-format json. */
interface ChevalResponse {
  content?: string;
  model?: string;
  provider?: string;
  usage?: { input_tokens?: number; output_tokens?: number };
  latency_ms?: number;
}

/** Parsed JSON error envelope from cheval stderr's last line (--json-errors). */
interface ChevalError {
  code?: string;
  message?: string;
  retryable?: boolean;
}

export class ChevalDelegateAdapter implements ILLMProvider {
  private readonly opts: Required<
    Pick<ChevalDelegateOptions, "model" | "timeoutMs" | "agent" | "pythonBin">
  > &
    Pick<
      ChevalDelegateOptions,
      "mockFixtureDir" | "mode" | "chevalScript" | "spawnFn"
    >;

  constructor(options: ChevalDelegateOptions) {
    if (!options.model) {
      throw new Error("ChevalDelegateAdapter: `model` is required");
    }

    if (options.mode === "daemon") {
      throw new LLMProviderError(
        "INVALID_REQUEST",
        "ChevalDelegateAdapter: daemon-mode is out of scope for Sprint 1 (T1.3 descoped). " +
          "Set mode=\"spawn\" or omit.",
      );
    }

    this.opts = {
      model: options.model,
      timeoutMs: options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      agent: options.agent ?? DEFAULT_AGENT,
      pythonBin: options.pythonBin ?? "python3",
      mockFixtureDir: options.mockFixtureDir,
      mode: options.mode ?? "spawn",
      chevalScript: options.chevalScript,
      spawnFn: options.spawnFn,
    };
  }

  async generateReview(request: ReviewRequest): Promise<ReviewResponse> {
    if (!request.systemPrompt || !request.userPrompt) {
      throw new LLMProviderError(
        "INVALID_REQUEST",
        "ChevalDelegateAdapter: systemPrompt and userPrompt are required",
      );
    }
    if (!Number.isFinite(request.maxOutputTokens) || request.maxOutputTokens <= 0) {
      throw new LLMProviderError(
        "INVALID_REQUEST",
        "ChevalDelegateAdapter: maxOutputTokens must be a positive integer",
      );
    }

    const scriptPath =
      this.opts.chevalScript ?? join(process.cwd(), CHEVAL_SCRIPT_REL);

    // AC-1.8 (a): credentials cross via env inheritance ONLY. We DO NOT touch
    // process.env keys; the child inherits the parent's env by default. Argv
    // and stdin are reserved for non-secret data (system prompt path, user
    // prompt path, model id, max tokens).
    const tempDir = mkdtempSync(join(tmpdir(), "cheval-delegate-"));
    const systemPath = join(tempDir, "system.txt");
    const inputPath = join(tempDir, "input.txt");

    let child: ReturnType<typeof spawn> | undefined;
    let killTimer: NodeJS.Timeout | undefined;
    let sigkillTimer: NodeJS.Timeout | undefined;
    let timedOut = false;

    const startedAt = Date.now();

    try {
      writeFileSync(systemPath, request.systemPrompt, { encoding: "utf8" });
      writeFileSync(inputPath, request.userPrompt, { encoding: "utf8" });

      const args = [
        scriptPath,
        "--agent",
        this.opts.agent,
        "--model",
        this.opts.model,
        "--system",
        systemPath,
        "--input",
        inputPath,
        "--max-tokens",
        String(request.maxOutputTokens),
        "--output-format",
        "json",
        "--json-errors",
        "--timeout",
        String(Math.ceil(this.opts.timeoutMs / 1000)),
      ];

      if (this.opts.mockFixtureDir) {
        // AC-1.2 passthrough. T1.5 lands the cheval-side flag handling; until
        // then cheval errors with INVALID_INPUT — which is the correct signal
        // that fixture-mode is requested but unavailable.
        args.push("--mock-fixture-dir", this.opts.mockFixtureDir);
      }

      const spawnImpl = this.opts.spawnFn ?? spawn;
      child = spawnImpl(this.opts.pythonBin, args, {
        stdio: ["ignore", "pipe", "pipe"],
        env: process.env,
        windowsHide: true,
      });

      let stdoutBuf = "";
      let stderrBuf = "";

      child.stdout?.setEncoding("utf8");
      child.stderr?.setEncoding("utf8");
      child.stdout?.on("data", (chunk: string) => {
        stdoutBuf += chunk;
      });
      child.stderr?.on("data", (chunk: string) => {
        stderrBuf += chunk;
      });

      // AC-1.9 (b): SIGTERM at timeout, SIGKILL at timeout+SIGKILL_GRACE_MS.
      killTimer = setTimeout(() => {
        timedOut = true;
        child?.kill("SIGTERM");
        sigkillTimer = setTimeout(() => {
          if (child && child.exitCode === null && child.signalCode === null) {
            child.kill("SIGKILL");
          }
        }, SIGKILL_GRACE_MS);
      }, this.opts.timeoutMs);

      const exitInfo = await new Promise<{ code: number | null; signal: NodeJS.Signals | null }>(
        (resolve, reject) => {
          child!.on("error", reject);
          child!.on("close", (code, signal) => resolve({ code, signal }));
        },
      );

      if (killTimer) clearTimeout(killTimer);
      if (sigkillTimer) clearTimeout(sigkillTimer);

      if (timedOut || exitInfo.signal === "SIGTERM" || exitInfo.signal === "SIGKILL") {
        throw new LLMProviderError(
          "TIMEOUT",
          `cheval-delegate: process exceeded timeout=${this.opts.timeoutMs}ms (signal=${exitInfo.signal ?? "internal"})`,
        );
      }

      if (exitInfo.code !== 0) {
        throw translateExitCode(exitInfo.code, stderrBuf);
      }

      // AC-1.9 (c): partial-stdout → typed retry-eligible error.
      const parsed = parseStdout(stdoutBuf);
      if (parsed === null) {
        throw new LLMProviderError(
          "PROVIDER_ERROR",
          "cheval-delegate: MalformedDelegateError — stdout was not parseable JSON (retry-eligible)",
        );
      }

      if (typeof parsed.content !== "string") {
        throw new LLMProviderError(
          "PROVIDER_ERROR",
          "cheval-delegate: MalformedDelegateError — response missing string `content`",
        );
      }

      const inputTokens = parsed.usage?.input_tokens ?? 0;
      const outputTokens = parsed.usage?.output_tokens ?? 0;
      const latencyFromCheval = parsed.latency_ms;
      const wallClockLatency = Date.now() - startedAt;

      return {
        content: parsed.content,
        inputTokens,
        outputTokens,
        model: parsed.model ?? this.opts.model,
        provider: parsed.provider,
        // Prefer cheval's reported provider-call latency. Fall back to our wall
        // clock (which includes Python startup) when cheval doesn't report.
        latencyMs:
          typeof latencyFromCheval === "number" ? latencyFromCheval : wallClockLatency,
      };
    } finally {
      try {
        rmSync(tempDir, { recursive: true, force: true });
      } catch {
        // Temp-dir cleanup is best-effort. Don't mask the real error.
      }
    }
  }
}

/**
 * Translate a cheval exit code + stderr tail into a typed LLMProviderError per
 * SDD §5.3 table. Stderr classification disambiguates exit-1 (RATE_LIMITED vs
 * PROVIDER_ERROR) by reading the JSON error envelope cheval emits last line.
 */
export function translateExitCode(
  exitCode: number | null,
  stderr: string,
): LLMProviderError {
  const tail = lastJsonLine(stderr);
  const chevalCode = tail?.code ?? "";
  const message = tail?.message ?? stderrPreview(stderr);

  // Detail string we attach to the user-facing message. Cheval already
  // redacts secrets on its side (cycle-099 lib/log-redactor.sh); we only
  // surface the classified code + redacted message tail.
  const detail = chevalCode ? `${chevalCode}: ${message}` : message;

  switch (exitCode) {
    case 1: {
      // SDD §5.3: exit 1 split by cheval error class. Cheval emits the class
      // name as the JSON `code` field (e.g., "RATE_LIMITED").
      let portCode: LLMProviderErrorCode;
      if (chevalCode === "RATE_LIMITED") {
        portCode = "RATE_LIMITED";
      } else {
        portCode = "PROVIDER_ERROR";
      }
      return new LLMProviderError(portCode, `cheval-delegate: ${detail}`);
    }
    case 2:
      return new LLMProviderError("INVALID_REQUEST", `cheval-delegate: ${detail}`);
    case 3:
      return new LLMProviderError("TIMEOUT", `cheval-delegate: ${detail}`);
    case 4:
      return new LLMProviderError("AUTH_ERROR", `cheval-delegate: ${detail}`);
    case 5:
      return new LLMProviderError("PROVIDER_ERROR", `cheval-delegate: ${detail}`);
    case 6:
      return new LLMProviderError("INVALID_REQUEST", `cheval-delegate: ${detail}`);
    case 7:
      return new LLMProviderError("TOKEN_LIMIT", `cheval-delegate: ${detail}`);
    case null:
      // Process didn't exit normally — treat as NETWORK so retry policy kicks in.
      return new LLMProviderError(
        "NETWORK",
        `cheval-delegate: process terminated without exit code (${detail})`,
      );
    default:
      return new LLMProviderError(
        "PROVIDER_ERROR",
        `cheval-delegate: unexpected exit code ${exitCode} (${detail})`,
      );
  }
}

/** Return the last JSON-decodable line of stderr, or null if none. */
function lastJsonLine(stderr: string): ChevalError | null {
  const lines = stderr.split(/\r?\n/).filter((l) => l.trim().length > 0);
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line.startsWith("{")) continue;
    try {
      const parsed = JSON.parse(line) as unknown;
      if (parsed && typeof parsed === "object") {
        return parsed as ChevalError;
      }
    } catch {
      // Keep walking — older diagnostic lines may not be JSON.
    }
  }
  return null;
}

/** Parse cheval stdout as a single JSON response. Returns null on parse error. */
function parseStdout(stdout: string): ChevalResponse | null {
  const trimmed = stdout.trim();
  if (!trimmed) return null;
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (parsed && typeof parsed === "object") {
      return parsed as ChevalResponse;
    }
    return null;
  } catch {
    return null;
  }
}

/** Best-effort stderr preview when no JSON error envelope was found. */
function stderrPreview(stderr: string): string {
  const trimmed = stderr.trim();
  if (!trimmed) return "(no stderr)";
  // Cap to a single line of ~256 chars to avoid leaking large payloads into
  // user-facing error text. Cheval's own redactor runs before this point.
  const head = trimmed.split(/\r?\n/).pop() ?? "";
  return head.length > 256 ? `${head.slice(0, 256)}…` : head;
}
