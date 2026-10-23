import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import {
  closeSync,
  constants,
  cpSync,
  existsSync,
  fstatSync,
  linkSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmdirSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { configureExecutionProfile } from "./configure-execution-profile.mjs";
import {
  runNpmFallbackInstaller,
  runPnpmInstaller,
} from "./install-report.mjs";
import { LOCKFILES } from "./package-manager.mjs";
import { WorkflowError } from "./workflow-metrics.mjs";

export const PNPM_VERSION = "11.25.0";
export const starterDirectory = fileURLToPath(
  new URL(
    "../skills/sites/templates/vinext-starter/",
    import.meta.url,
  ),
);
const assetsDirectory = fileURLToPath(
  new URL("../assets/pnpm/vinext/", import.meta.url),
);
const npmInputs = ["package.json", "package-lock.json", ".npmrc"];
const pnpmInputs = ["pnpm-lock.yaml", "pnpm-workspace.yaml"];
const pendingFilename = "pnpm-bootstrap-pending";

// Setup records intent only for a new bundled starter. Keep it across failed
// attempts so changed inputs cannot silently turn a pnpm retry into npm.
export function hasPendingPnpmBootstrap(project = process.cwd()) {
  const storage = lstatSync(path.join(project, ".sites-runtime"), {
    throwIfNoEntry: false,
  });
  // Established projects can use SITES_RUNTIME_ROOT when this path is a file.
  // Such a path cannot contain the new-project setup marker.
  if (!storage || storage.isFile()) return false;
  const runtime = ownedRuntimeDirectory(project);
  let descriptor;
  try {
    descriptor = openSync(
      path.join(runtime, pendingFilename),
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
    if (
      !fstatSync(descriptor).isFile() ||
      readFileSync(descriptor, "utf8") !== "pnpm\n"
    ) {
      throw new Error("Expected a pending pnpm setup marker");
    }
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw new WorkflowError(
      "The pending pnpm setup marker is invalid; inspect .sites-runtime before retrying.",
      78,
    );
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

export function markPendingPnpmBootstrap(project = process.cwd()) {
  if (hasPendingPnpmBootstrap(project)) return;
  writeFileSync(
    path.join(ownedRuntimeDirectory(project), pendingFilename),
    "pnpm\n",
    { flag: "wx", mode: 0o600 },
  );
}

function clearPendingPnpmBootstrap(project) {
  if (hasPendingPnpmBootstrap(project))
    unlinkSync(path.join(ownedRuntimeDirectory(project), pendingFilename));
}

function unexpectedLockfiles(manager) {
  const selected = manager === "pnpm" ? "pnpm-lock.yaml" : "package-lock.json";
  return [
    ...Object.values(LOCKFILES)
      .flat()
      .filter((filename) => filename !== selected),
    ...(manager === "npm" ? ["pnpm-workspace.yaml"] : []),
  ];
}

function rejectUnexpectedLocks(project, manager) {
  if (
    unexpectedLockfiles(manager).some((name) =>
      lstatSync(path.join(project, name), { throwIfNoEntry: false }),
    )
  ) {
    throw new WorkflowError(
      "Another package-manager lock or configuration appeared during setup; adoption stopped.",
      78,
    );
  }
}

function fileHash(filename) {
  if (!lstatSync(filename).isFile())
    throw new Error("Expected a regular bootstrap input");
  return createHash("sha256").update(readFileSync(filename)).digest("hex");
}

// This receipt binds the imported pnpm graph to the exact shipped npm inputs.
// A starter update must regenerate/review both locks before setup can resume.
export function verifyBootstrapInputs() {
  const receipt = JSON.parse(
    readFileSync(path.join(assetsDirectory, "bootstrap.json"), "utf8"),
  );
  if (
    receipt.version !== 1 ||
    receipt.pnpm_version !== PNPM_VERSION ||
    Object.keys(receipt.sha256 ?? {})
      .sort()
      .join() !== [...npmInputs, ...pnpmInputs].sort().join()
  ) {
    throw new WorkflowError("The pnpm bootstrap receipt is invalid.", 78);
  }
  for (const [directory, names] of [
    [starterDirectory, npmInputs],
    [assetsDirectory, pnpmInputs],
  ]) {
    for (const name of names) {
      if (fileHash(path.join(directory, name)) !== receipt.sha256[name]) {
        throw new WorkflowError(
          "The pnpm bootstrap inputs have changed; regenerate the paired lockfiles.",
          78,
        );
      }
    }
  }
  return receipt;
}

export function isFreshStarter(project = process.cwd()) {
  const receipt = verifyBootstrapInputs();
  try {
    if (
      [
        "node_modules",
        "pnpm-lock.yaml",
        "pnpm-workspace.yaml",
        "npm-shrinkwrap.json",
        "yarn.lock",
        "bun.lock",
        "bun.lockb",
      ].some((name) => existsSync(path.join(project, name)))
    )
      return false;
    return npmInputs.every(
      (name) => fileHash(path.join(project, name)) === receipt.sha256[name],
    );
  } catch {
    return false;
  }
}

export function ownedRuntimeDirectory(project) {
  const resolved = realpathSync(project);
  const directory = path.join(resolved, ".sites-runtime");
  try {
    mkdirSync(directory, { mode: 0o700 });
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
  }
  if (
    !lstatSync(directory).isDirectory() ||
    realpathSync(directory) !== directory
  ) {
    throw new WorkflowError(
      "Sites runtime storage must be a directory inside this project.",
      78,
    );
  }
  return directory;
}

function readLocalExecutionProfile(runtime) {
  let descriptor;
  try {
    descriptor = openSync(
      path.join(runtime, "execution-profile.json"),
      constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK,
    );
    if (!fstatSync(descriptor).isFile())
      throw new Error("Expected a regular execution profile");
    const { executionProfile } = JSON.parse(readFileSync(descriptor, "utf8"));
    if (!["portable", "managed-linux"].includes(executionProfile))
      throw new Error("Invalid execution profile");
    return executionProfile;
  } catch (error) {
    // Match the starter's clean-clone default without following project links.
    if (error.code === "ENOENT") return "portable";
    throw new WorkflowError(
      "The local execution profile is invalid; rerun configure-execution-profile.mjs with the intended profile.",
      78,
    );
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

// Diagnostics exercise Work's managed build path. Real setup passes its chosen profile.
export function stagePnpmProject(
  parent,
  { executionProfile = "managed-linux" } = {},
) {
  verifyBootstrapInputs();
  const directory = mkdtempSync(path.join(parent, "pnpm-validation-"));
  try {
    cpSync(starterDirectory, directory, { recursive: true, force: true });
    configureExecutionProfile(directory, executionProfile);
    for (const name of pnpmInputs)
      cpSync(path.join(assetsDirectory, name), path.join(directory, name));
    const manifest = JSON.parse(
      readFileSync(path.join(directory, "package.json"), "utf8"),
    );
    manifest.packageManager = `pnpm@${PNPM_VERSION}`;
    manifest.scripts["install:ci"] = "bash scripts/install-pnpm.sh";
    writeFileSync(
      path.join(directory, "package.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    rmSync(path.join(directory, "package-lock.json"));
    return directory;
  } catch (error) {
    rmSync(directory, { recursive: true, force: true });
    throw error;
  }
}

function stageNpmProject(parent, executionProfile) {
  verifyBootstrapInputs();
  const directory = mkdtempSync(path.join(parent, "pnpm-validation-"));
  try {
    cpSync(starterDirectory, directory, { recursive: true, force: true });
    configureExecutionProfile(directory, executionProfile);
    return directory;
  } catch (error) {
    rmSync(directory, { recursive: true, force: true });
    throw error;
  }
}

async function acquireInstallLock(runtime) {
  // Use the same kernel lock as the existing npm installer. A pipe-held helper
  // releases it even if this parent dies; there is no stale mkdir lock to clear.
  const fd = openSync(
    path.join(runtime, "install.lock"),
    constants.O_CREAT |
      constants.O_RDWR |
      constants.O_NOFOLLOW |
      constants.O_NONBLOCK,
    0o600,
  );
  let child;
  try {
    if (!fstatSync(fd).isFile())
      throw new WorkflowError("The install lock must be a regular file.", 78);
    child = spawn(
      "bash",
      [
        "-c",
        'flock -n -E 75 3 || exit "$?"; printf "locked\\n"; cat >/dev/null',
      ],
      {
        stdio: ["pipe", "pipe", "inherit", fd],
      },
    );
  } finally {
    closeSync(fd);
  }
  let active = true;
  const closed = new Promise((resolve) => {
    child.once("close", () => {
      active = false;
      resolve();
    });
  });
  child.stdin.on("error", () => {});
  await new Promise((resolve, reject) => {
    child.once("error", () =>
      reject(
        new WorkflowError("Unable to acquire the project install lock.", 69),
      ),
    );
    child.once("close", () =>
      reject(
        new WorkflowError("Another dependency install owns this project.", 75),
      ),
    );
    child.stdout.once("data", (data) =>
      data.toString().trim() === "locked"
        ? resolve()
        : reject(
            new WorkflowError(
              "Unable to acquire the project install lock.",
              70,
            ),
          ),
    );
  });
  return {
    get active() {
      return active;
    },
    async release() {
      child.stdin.end();
      await closed;
    },
  };
}

function adoptInstall(stage, project, manager) {
  const receipt = verifyBootstrapInputs();
  // Keep the claimed inodes outside disposable staging, including on success.
  // An author with an already-open file can still write its inode after rename;
  // retaining it preserves that edit rather than deleting it during cleanup.
  const recovery = mkdtempSync(
    path.join(path.dirname(stage), "pnpm-adoption-inputs-"),
  );
  const claimed = [];
  const published = [];
  let reservation;
  const sameInode = (filename, stat) => {
    try {
      const current = lstatSync(filename);
      return current.dev === stat.dev && current.ino === stat.ino;
    } catch {
      return false;
    }
  };
  try {
    // The existing npm lock is expected until claimed; every other incoming
    // lock/config must still be absent before finalization begins.
    rejectUnexpectedLocks(project, "npm");
    // Claim the actual files atomically, then validate those claimed bytes.
    // A check followed by replacing the still-live pathname can lose edits.
    for (const name of npmInputs) {
      renameSync(path.join(project, name), path.join(recovery, name));
      claimed.push(name);
    }
    const validateClaims = () => {
      if (
        npmInputs.some(
          (name) =>
            fileHash(path.join(recovery, name)) !== receipt.sha256[name],
        )
      ) {
        throw new WorkflowError(
          "Dependency inputs changed during installation; adoption stopped.",
          78,
        );
      }
    };
    validateClaims();

    // Reserve an absent directory first. rename cannot replace it if another
    // writer populates it, and an existing module tree is never overwritten.
    const modules = path.join(project, "node_modules");
    mkdirSync(modules);
    reservation = lstatSync(modules);
    renameSync(path.join(stage, "node_modules"), modules);
    published.push({ name: "node_modules", stat: lstatSync(modules) });
    reservation = undefined;
    const names =
      manager === "pnpm"
        ? [".npmrc", ...pnpmInputs, "package.json"]
        : [".npmrc", "package-lock.json", "package.json"];
    for (const name of names) {
      // Exclusive publication fails if an author recreated the claimed path.
      linkSync(path.join(stage, name), path.join(project, name));
      published.push({ name, stat: lstatSync(path.join(project, name)) });
    }
    validateClaims();
    rejectUnexpectedLocks(project, manager);
    return recovery;
  } catch (error) {
    for (const { name, stat } of published.reverse()) {
      const target = path.join(project, name);
      if (sameInode(target, stat)) {
        // Preserve produced files too: a concurrent writer may have edited one.
        try {
          renameSync(target, path.join(recovery, `produced-${name}`));
        } catch {}
      }
    }
    if (
      reservation &&
      sameInode(path.join(project, "node_modules"), reservation)
    ) {
      try {
        rmdirSync(path.join(project, "node_modules"));
      } catch {}
    }
    for (const name of claimed) {
      // Never replace a new author-created file while restoring old inputs.
      try {
        linkSync(path.join(recovery, name), path.join(project, name));
      } catch {}
    }
    throw new WorkflowError(
      `Dependency adoption stopped: ${error.message}. Claimed inputs and any produced files are preserved at ${recovery}; inspect conflicts before retrying.`,
      78,
    );
  }
}

// Both installers run in disposable checkouts. Only successful installs claim
// the real inputs for validated publication; conflicts retain recovery files.
export async function bootstrapPnpm(project = process.cwd()) {
  if (!isFreshStarter(project)) {
    throw new WorkflowError(
      "pnpm setup requires an unchanged starter without installed dependencies; preserve the failed setup and repair its cause before retrying. Automatic npm fallback is unavailable for modified inputs.",
      78,
    );
  }
  const runtime = ownedRuntimeDirectory(project);
  const executionProfile = readLocalExecutionProfile(runtime);
  let lock;
  let stage;
  let result;
  let failure;
  let receivedSignal;
  const handlers = new Map(
    ["SIGINT", "SIGHUP", "SIGTERM"].map((signal) => [
      signal,
      () => {
        receivedSignal ??= signal;
      },
    ]),
  );
  for (const [name, handler] of handlers) process.on(name, handler);
  try {
    lock = await acquireInstallLock(runtime);
    if (!receivedSignal) {
      if (!isFreshStarter(project)) {
        throw new WorkflowError(
          "Project dependencies changed before pnpm setup acquired the install lock; automatic npm fallback is unavailable.",
          78,
        );
      }
      markPendingPnpmBootstrap(project);
      let manager = "pnpm";
      if (
        process.env.SITES_PNPM_BIN &&
        existsSync(process.env.SITES_PNPM_BIN)
      ) {
        stage = stagePnpmProject(runtime, { executionProfile });
        result = await runPnpmInstaller(stage, ["--require-shared"], {
          resetContext: true,
        });
      } else {
        result = { code: 69, signal: null };
      }
      if (
        !result.signal &&
        !receivedSignal &&
        [69, 70, 75, 124, 137, 126, 127].includes(result.code)
      ) {
        if (!lock.active || !isFreshStarter(project)) {
          throw new WorkflowError(
            "Dependencies changed during pnpm setup; automatic npm fallback is unavailable.",
            78,
          );
        }
        if (stage) rmSync(stage, { recursive: true, force: true });
        stage = stageNpmProject(runtime, executionProfile);
        manager = "npm";
        // npm is now selected even if its install fails. A no-flag retry must
        // repair npm, not start another pnpm attempt against the same starter.
        clearPendingPnpmBootstrap(project);
        process.stdout.write(
          "[sites] pnpm setup unavailable; using the existing npm installer in a temporary checkout\n",
        );
        result = await runNpmFallbackInstaller(stage);
      }
      if (result.code === 0 && !result.signal && !receivedSignal) {
        // Authoring can overlap installation, but dependency edits must not be lost.
        if (!lock.active || !isFreshStarter(project)) {
          throw new WorkflowError(
            "Project dependencies changed during setup; pnpm adoption was not applied.",
            78,
          );
        }
        // Hold cancellation observation across finalization. Signals arriving
        // during synchronous publication propagate after manager finalization
        // or recovery that preserves the original and conflicting input files.
        const recovery = adoptInstall(stage, project, manager);
        clearPendingPnpmBootstrap(project);
        process.stdout.write(
          `[sites] this project now uses ${manager} and its own node_modules; previous inputs retained at ${recovery}\n`,
        );
      }
    }
  } catch (error) {
    failure = error;
  } finally {
    try {
      try {
        if (stage) rmSync(stage, { recursive: true, force: true });
      } finally {
        if (lock) await lock.release();
      }
    } finally {
      for (const [name, handler] of handlers)
        process.removeListener(name, handler);
    }
  }
  if (receivedSignal)
    return { ...result, code: result?.code ?? 1, signal: receivedSignal };
  if (failure) throw failure;
  return result;
}
