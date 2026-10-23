import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync, rmSync } from "node:fs";
import { performance } from "node:perf_hooks";
import {
  ownedRuntimeDirectory, PNPM_VERSION, stagePnpmProject, verifyBootstrapInputs,
} from "./pnpm-bootstrap.mjs";
import { runPnpmInstaller } from "./install-report.mjs";
import { runCommand, runMeasuredOperation, WorkflowError } from "./workflow-metrics.mjs";

// Explicit diagnostics only: never called by ordinary setup or container startup.
// Child failures are results of this diagnostic, not real Site install outcomes.
// Consumers (including image CI) must inspect the final `ok` field.
await runMeasuredOperation(async () => {
  const args = process.argv.slice(2);
  const checks = ["readiness", "store", "install", "build", "reuse"];
  if (args.length !== 2 || args[0] !== "--check" || !checks.includes(args[1])) {
    throw new WorkflowError("Use validate-pnpm.mjs --check readiness|store|install|build|reuse.", 64);
  }
  const limit = checks.indexOf(args[1]);
  const started = performance.now();
  const observations = [];
  const measurements = [];
  let project;
  let second;
  let signal;
  let state = "unknown";
  let stopped = false;

  function record(stage, outcome, reason, elapsed) {
    const dimensions = { stage, outcome, reason, store_state: state };
    observations.push({ ...dimensions, ...(elapsed === undefined ? {} : { duration_ms: elapsed }) });
    measurements.push({ name: "result", value: 1, dimensions });
    if (elapsed !== undefined && outcome !== "skipped") measurements.push({ name: "duration_ms", value: elapsed, dimensions });
    if (outcome !== "success") stopped = true;
  }

  try {
    const readyAt = performance.now();
    verifyBootstrapInputs();
    const executable = process.env.SITES_PNPM_BIN;
    if (!executable || !existsSync(executable) || !lstatSync(executable).isFile()) {
      record("readiness", "skipped", "image_unavailable");
    } else {
      let version;
      try {
        version = execFileSync(process.execPath, [executable, "--version"], {
          encoding: "utf8", timeout: 30_000, maxBuffer: 4096, stdio: ["ignore", "pipe", "pipe"],
        }).trim();
      } catch (error) {
        signal = error.signal === "SIGINT" || error.signal === "SIGHUP" ? error.signal : undefined;
        record("readiness", signal ? "cancelled" : "error", signal ? "cancelled" : error.code === "ETIMEDOUT" ? "timeout" : "image_unavailable", performance.now() - readyAt);
      }
      if (!stopped) record("readiness", version === PNPM_VERSION ? "success" : "error", version === PNPM_VERSION ? "none" : "image_unavailable", performance.now() - readyAt);
    }
    if (!stopped && limit > 0) {
      const runtime = ownedRuntimeDirectory(process.cwd());
      project = stagePnpmProject(runtime);
      for (const stage of checks.slice(1, limit + 1)) {
        if (stopped) break;
        const stageAt = performance.now();
        let result;
        if (stage === "build") {
          const env = { ...process.env };
          delete env.SITES_ENV_READY;
          delete env.SITES_PROJECT_ROOT;
          delete env.SITES_RUNTIME_ROOT;
          result = await runCommand(["timeout", "--signal=TERM", "--kill-after=15s", "8m", "npm", "--prefix", ".", "--workspaces=false", "run", "build"], { cwd: project, env, preserveCancellation: true });
        } else {
          if (stage === "reuse") second = stagePnpmProject(runtime);
          result = await runPnpmInstaller(second ?? project, stage === "store" ? ["--require-shared", "--prepare-store"] : ["--require-shared"], { resetContext: true });
          state = result.storeState ?? "unknown";
        }
        signal = result.signal;
        const success = result.code === 0 && !signal;
        const reason = success ? "none" : signal ? "cancelled" : [124, 137].includes(result.code) ? "timeout" :
          stage === "store" ? "store_unavailable" : stage === "build" ? "build_failed" : stage === "reuse" ? "reuse_failed" : "install_failed";
        record(stage, success ? "success" : signal ? "cancelled" : "error", reason, performance.now() - stageAt);
        if (success && stage === "reuse" && state !== "reused") {
          // A successful second install alone does not establish same-store reuse.
          record("validation", "error", "reuse_failed", performance.now() - started);
        }
      }
    }
  } catch {
    record("validation", "error", "validation_failed", performance.now() - started);
  } finally {
    for (const scratch of [second, project]) {
      if (scratch) rmSync(scratch, { recursive: true, force: true });
    }
  }
  const failure = observations.find((item) => item.outcome !== "success");
  if (!observations.some((item) => item.stage === "validation")) {
    record("validation", failure?.outcome ?? "success", failure?.reason ?? "none", failure?.outcome === "skipped" ? undefined : performance.now() - started);
  }
  let pluginVersion = "unknown";
  try { pluginVersion = JSON.parse(readFileSync(new URL("../.codex-plugin/plugin.json", import.meta.url), "utf8")).version; } catch {}
  process.stdout.write(`[sites pnpm validation] ${JSON.stringify({
    version: 1, ok: !failure, check: args[1], pnpm_version: PNPM_VERSION,
    plugin_version: pluginVersion, observations,
  })}\n`);
  // Failed probes remain visible in their own metrics. A completed diagnostic
  // exits zero because Core only reads sidecars from completed commands. Real
  // cancellation still propagates; a crashed wrapper uses backend fallback.
  return { code: 0, signal, measurements };
});
