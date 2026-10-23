import {
  readProjectManifest,
  resolveYarnMajor,
  selectPackageManager,
} from "./package-manager.mjs";
import { runPnpmInstaller, runReportedInstall } from "./install-report.mjs";
import {
  bootstrapPnpm,
  hasPendingPnpmBootstrap,
  PNPM_VERSION,
} from "./pnpm-bootstrap.mjs";
import {
  configureExecutionProfile,
  detectExecutionProfile,
} from "./configure-execution-profile.mjs";
import { runMeasuredOperation, WorkflowError } from "./workflow-metrics.mjs";

// Preserve project install scripts and let the package manager handle its dependencies.
await runMeasuredOperation(async () => {
  if (process.argv.length > 2)
    throw new WorkflowError(
      "Use install-dependencies.mjs without arguments.",
      64,
    );
  const pending = hasPendingPnpmBootstrap();
  const manifest = readProjectManifest({ required: false });
  const manager = selectPackageManager(manifest);
  if (!manifest) {
    if (pending)
      throw new WorkflowError(
        "package.json is missing during pending pnpm setup; restore its dependency inputs before retrying.",
        78,
      );
    if (manager.hasLockfile)
      throw new WorkflowError("A lockfile exists without package.json.");
    return skipInstall();
  }
  if (pending) configureExecutionProfile(process.cwd());
  const managed = detectExecutionProfile() === "managed-linux";
  if (pending && !managed) {
    throw new WorkflowError(
      "This Site has unfinished managed pnpm setup. Resume that setup in its managed environment before moving the project; a portable install cannot silently replace it with npm.",
      78,
    );
  }
  if (pending && manager.name !== "npm") {
    throw new WorkflowError(
      "Package-manager inputs changed during pending pnpm setup. Inspect the project and its recovery files before clearing .sites-runtime/pnpm-bootstrap-pending.",
      78,
    );
  }
  if (manager.name === "npm" && managed && pending) {
    return bootstrapPnpm();
  }
  // Starter scripts own profile-specific cache, runtime setup, and timeouts.
  const installCi = manifest.scripts?.["install:ci"];
  if (installCi !== undefined) {
    if (typeof installCi !== "string" || !installCi.trim()) {
      throw new WorkflowError(
        "The install:ci script must be a nonempty string.",
      );
    }
    if (
      manager.name === "pnpm" &&
      manager.version === PNPM_VERSION &&
      installCi === "bash scripts/install-pnpm.sh"
    ) {
      return runPnpmInstaller(process.cwd());
    }
    return runReportedInstall(
      [
        manager.name,
        ...(manager.name === "npm"
          ? ["--prefix", ".", "--workspaces=false"]
          : []),
        "run",
        "install:ci",
      ],
      { reportsSeed: true },
    );
  }
  // Even dependency-free roots can need workspace linking or implicit install hooks.
  return runReportedInstall(installCommand(manager));
});

function installCommand({ name, version, hasLockfile }) {
  if (name === "npm") return ["npm", hasLockfile ? "ci" : "install"];
  if (name === "pnpm" || name === "bun") {
    return hasLockfile
      ? [name, "install", "--frozen-lockfile"]
      : [name, "install"];
  }
  if (resolveYarnMajor(version) === 1) {
    return hasLockfile
      ? ["yarn", "install", "--frozen-lockfile", "--non-interactive"]
      : ["yarn", "install", "--non-interactive"];
  }
  return ["yarn", "install", hasLockfile ? "--immutable" : "--no-immutable"];
}

function skipInstall() {
  // No installer ran: succeed with an empty measurement list, not a latency sample.
  process.stdout.write("No dependency installation is needed.\n");
  return { code: 0, skipped: true };
}
