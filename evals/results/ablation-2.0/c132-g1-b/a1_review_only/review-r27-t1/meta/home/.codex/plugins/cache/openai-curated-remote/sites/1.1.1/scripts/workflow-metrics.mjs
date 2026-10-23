import { spawn } from "node:child_process";
import {
  closeSync,
  constants,
  fstatSync,
  ftruncateSync,
  openSync,
  writeFileSync,
} from "node:fs";
import { constants as osConstants } from "node:os";
import { performance } from "node:perf_hooks";

// Workflow scripts choose what to run. This module handles process results and
// writes the duration file that Codex turns into plugin analytics events.
export class WorkflowError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

function closeMetricsOutput(descriptor) {
  if (descriptor === undefined) return;
  try {
    closeSync(descriptor);
  } catch {}
}

function openMetricsOutput() {
  // Codex creates this file; scripts must neither create nor replace it.
  const output = process.env.CODEX_PLUGIN_METRICS_OUTPUT;
  if (!output || !constants.O_NOFOLLOW) return undefined;

  let descriptor;
  try {
    // Pin the host-owned inode before starting the command. Never create a file,
    // follow the final symlink, or block while opening a FIFO or device.
    descriptor = openSync(
      output,
      constants.O_WRONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
    if (fstatSync(descriptor).isFile()) return descriptor;
  } catch {
    // Telemetry availability must not affect the command.
  }
  closeMetricsOutput(descriptor);
  return undefined;
}

function writeMetrics(descriptor, startedAt, { code, signal, skipped, dimensions = {}, measurements, additionalMeasurements = [] }) {
  if (descriptor === undefined) return;
  try {
    const value = Math.max(0, performance.now() - startedAt);
    if (!Number.isFinite(value)) return;
    const outcome = signal ? "cancelled" : code === 0 ? "success" : "error";
    const payload = {
      version: 1,
      // A skipped install is not a zero-duration installation sample.
      measurements: skipped
        ? []
        : measurements ?? [
          { name: "duration_ms", value, dimensions: { ...dimensions, outcome } },
          ...additionalMeasurements,
        ],
    };
    ftruncateSync(descriptor, 0);
    writeFileSync(descriptor, `${JSON.stringify(payload)}\n`);
  } catch {
    // Do not log the sidecar path, command, environment, or command output.
  } finally {
    closeMetricsOutput(descriptor);
  }
}

// Spawn the explicit executable and wait for the child, including its output.
export function runCommand([executable, ...args], { windowsVerbatimArguments = false, env = process.env, cwd = process.cwd(), preserveCancellation = false } = {}) {
  return new Promise((resolve) => {
    let child;
    let finished = false;
    let receivedSignal;
    // Exec owns cancellation of the inherited process group. Observe its signals
    // and wait for the child; relaying TERM would deliver it twice during cleanup.
    // PID-only process-tree termination must be handled by the runtime.
    const observe = (signal) => () => { receivedSignal ??= signal; };
    const signalHandlers = new Map(["SIGINT", "SIGHUP", "SIGTERM"].map((signal) => [signal, observe(signal)]));
    const finish = (code, signal, startError) => {
      // A failed spawn can emit both error and close; settle only once.
      if (finished) return;
      finished = true;
      for (const [name, handler] of signalHandlers) process.removeListener(name, handler);
      // A child may handle TERM and exit with an operational error. Preserve the
      // caller's cancellation so an opt-in installer cannot start npm afterward.
      resolve({
        code,
        signal: preserveCancellation ? receivedSignal ?? signal : signal,
        ...(startError ? { startError } : {}),
      });
    };
    const failedToStart = (error) => {
      const code = error.code === "ENOENT" ? 127 : error.code === "EACCES" ? 126 : 1;
      process.stderr.write("Unable to start the Sites workflow command.\n");
      finish(code, null, error.code);
    };

    try {
      // Keep the caller's cwd, environment, stdio, and process group. The caller's
      // exec/timeout owns group cancellation; detaching would escape that group.
      child = spawn(executable, args, { stdio: "inherit", windowsVerbatimArguments, env, cwd });
      child.once("error", failedToStart);
      child.once("close", finish);
      for (const [name, handler] of signalHandlers) process.on(name, handler);
    } catch (error) {
      failedToStart(error);
    }
  });
}

// Time the whole operation, including in-process work such as template copying.
// Telemetry is best-effort; the caller always receives the operation's result.
export async function runMeasuredOperation(operation) {
  const descriptor = openMetricsOutput();
  const startedAt = performance.now();
  let result;
  try {
    result = await operation();
  } catch (error) {
    process.stderr.write(
      `${error instanceof WorkflowError ? error.message : "Unable to complete the Sites workflow operation."}\n`,
    );
    result = { code: error instanceof WorkflowError ? error.exitCode : 1 };
  }

  writeMetrics(descriptor, startedAt, result);
  if (!result.signal) {
    process.exitCode = result.code ?? 1;
    return;
  }

  // Preserve signal termination after writing metrics. The numeric exit code
  // remains a fallback if this platform cannot re-raise the signal.
  process.exitCode = 128 + (osConstants.signals[result.signal] ?? 0);
  try {
    process.kill(process.pid, result.signal);
  } catch {}
}

export async function runMeasuredCommand(command) {
  await runMeasuredOperation(() => runCommand(command));
}
