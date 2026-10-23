import { closeSync, mkdtempSync, openSync, readSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runPackageManager } from "./package-manager.mjs";
import { runCommand } from "./workflow-metrics.mjs";

// These describe the image-seed decision, not per-package cache hits. npm can
// still download missing packages after a matching seed is copied.
const CACHE_SEED_RESULTS = new Set([
  "seed_used", // A seed matching the project's lockfile was copied into its cache.
  "seed_unavailable", // No configured image-seed directory was available.
  "seed_lockfile_mismatch", // The seed marker did not match the project's lockfile hash.
  "decision_unavailable", // Old/custom installer or report I/O/format failure.
  "not_applicable", // No seed report requested, e.g. npm ci without an install:ci script.
]);
const REPORT_LIMIT = 4096;
const MAX_PACKAGES = 100_000;

function disposeReport(report) {
  if (!report) return;
  try { closeSync(report.descriptor); } catch {}
  try { rmSync(report.directory, { recursive: true, force: true }); } catch {}
}

function createReport() {
  let report;
  try {
    const directory = mkdtempSync(join(tmpdir(), "sites-install-"));
    report = { directory, path: join(directory, "report.json") };
    report.descriptor = openSync(report.path, "wx+", 0o600);
    return report;
  } catch {
    disposeReport(report);
    return undefined;
  }
}

// Old/custom installers may leave the report empty. Creation/read failures,
// invalid JSON, oversized reports, or unsupported versions/values produce
// decision_unavailable.
// None of these establishes that the image seed was missing.
function readInstallReport(report) {
  const unavailable = { cache_seed: "decision_unavailable", store_scope: "unknown", store_state: "unknown" };
  if (!report) return unavailable;
  try {
    // Read the original private inode, not a path the child may have replaced.
    // Bound the read even if a surviving subprocess keeps writing to the file.
    const buffer = Buffer.alloc(REPORT_LIMIT + 1);
    const length = readSync(report.descriptor, buffer, 0, buffer.length, 0);
    if (length > REPORT_LIMIT) return unavailable;
    const value = JSON.parse(buffer.subarray(0, length).toString("utf8"));
    if (value?.version === 1 && CACHE_SEED_RESULTS.has(value.cache_seed)) {
      return {
        cache_seed: value.cache_seed,
        store_scope: ["workspace", "project"].includes(value.store_scope) ? value.store_scope : "unknown",
        store_state: ["created", "seeded", "reused", "unavailable"].includes(value.store_state) ? value.store_state : "unknown",
        ...([value.packages_reused, value.packages_downloaded].every((count) => Number.isSafeInteger(count) && count >= 0)
          && value.packages_reused + value.packages_downloaded > 0
          && value.packages_reused + value.packages_downloaded <= MAX_PACKAGES
          ? { packages_reused: value.packages_reused, packages_downloaded: value.packages_downloaded } : {}),
      };
    }
  } catch {}
  return unavailable;
}

export async function runReportedInstall(command, { reportsSeed = false } = {}) {
  return reportedInstall(command, { reportsSeed, packageManager: command[0], execute: runPackageManager });
}

// The Work image has a private, version-checked pnpm. Calling its project helper
// directly also works when no global pnpm shim is on PATH.
// Real repairs keep runtime overrides; scratch callers explicitly reset them.
export async function runPnpmInstaller(project, args = [], { resetContext = false } = {}) {
  return reportedInstall(["bash", "scripts/install-pnpm.sh", ...args], {
    reportsSeed: true,
    packageManager: "pnpm",
    execute: runCommand,
    cwd: project,
    resetContext,
  });
}

// Initial fallback runs the unchanged npm installer in a canonical scratch
// checkout while bootstrap keeps the actual project's installation lease.
export async function runNpmFallbackInstaller(project) {
  return reportedInstall(["npm", "--prefix", ".", "--workspaces=false", "run", "install:ci"], {
    reportsSeed: true,
    packageManager: "npm",
    execute: runCommand,
    cwd: project,
    preserveCancellation: true,
    resetContext: true,
  });
}

async function reportedInstall(command, { reportsSeed, packageManager, execute, cwd, preserveCancellation = packageManager === "pnpm", resetContext = false }) {
  // Metadata is installer-reported, not an attestation of package contents.
  // Old/custom scripts emit no report and must not be counted as cache misses.
  const report = reportsSeed && (packageManager === "pnpm" || process.env.CODEX_PLUGIN_METRICS_OUTPUT)
    ? createReport()
    : undefined;
  const env = { ...process.env };
  delete env.SITES_INSTALL_REPORT_PATH;
  if (resetContext) {
    // The caller may itself be inside a Sites shell. A scratch project must
    // derive its own roots instead of inheriting the real Site's runtime dirs.
    delete env.SITES_ENV_READY;
    delete env.SITES_PROJECT_ROOT;
    delete env.SITES_RUNTIME_ROOT;
  }
  if (report) env.SITES_INSTALL_REPORT_PATH = report.path;
  try {
    const result = await execute(command, { env, cwd, preserveCancellation });
    const metadata = readInstallReport(report);
    const dimensions = {
      package_manager: packageManager,
      cache_seed: reportsSeed ? metadata.cache_seed : "not_applicable",
      store_scope: packageManager === "pnpm" ? metadata.store_scope : "unknown",
    };
    return {
      ...result,
      dimensions,
      storeState: metadata.store_state,
      additionalMeasurements: result.code === 0 && !result.signal && ["npm", "pnpm"].includes(packageManager)
        && metadata.packages_reused !== undefined
        ? ["packages_reused", "packages_downloaded"].map((name) => ({
          name, value: metadata[name], dimensions: { ...dimensions, outcome: "success" },
        })) : [],
    };
  } finally {
    disposeReport(report);
  }
}
