import { spawnSync } from "node:child_process";
import { lstatSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { devNull, tmpdir } from "node:os";
import path from "node:path";
import { WorkflowError } from "./workflow-metrics.mjs";

const destinationHelp =
  "Place the archive outside the Site checkout or under its ignored outputs/ directory.";

function inside(directory, filename) {
  const relative = path.relative(directory, filename);
  return (
    !relative ||
    (!relative.startsWith(`..${path.sep}`) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  );
}

// Resolve existing ancestors even when the output directory has not been made.
// A path outside the checkout can otherwise point back into source through a link.
function resolveDestination(filename) {
  const suffix = [];
  let ancestor = filename;
  while (!lstatSync(ancestor, { throwIfNoEntry: false })) {
    suffix.unshift(path.basename(ancestor));
    const parent = path.dirname(ancestor);
    if (parent === ancestor) throw new WorkflowError(destinationHelp, 64);
    ancestor = parent;
  }
  return path.join(realpathSync(ancestor), ...suffix);
}

function ignoredOutput(project, filename) {
  const relative = path.relative(project, filename);
  const env = { ...process.env };
  for (const key of [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
  ])
    delete env[key];
  const options = { cwd: project, encoding: "utf8", windowsHide: true, env };
  const config = ["-c", `core.excludesFile=${devNull}`];
  const root = spawnSync(
    "git",
    [...config, "rev-parse", "--show-toplevel"],
    options,
  );
  if (root.status === 0 && realpathSync(root.stdout.trim()) === project) {
    // Tracked artifacts remain tracked despite .gitignore. Do not accept them.
    return (
      spawnSync(
        "git",
        [...config, "check-ignore", "--quiet", "--", relative],
        options,
      ).status === 0
    );
  }

  // Setup may precede Git initialization. Probe the checkout's own ignore files
  // using empty temporary metadata, without altering its repository or config.
  const probe = mkdtempSync(path.join(tmpdir(), "sites-ignore-"));
  try {
    const initialized = spawnSync(
      "git",
      [...config, "init", "--quiet", probe],
      options,
    );
    if (initialized.status !== 0) return false;
    return (
      spawnSync(
        "git",
        [
          ...config,
          `--git-dir=${path.join(probe, ".git")}`,
          `--work-tree=${project}`,
          "check-ignore",
          "--quiet",
          "--",
          relative,
        ],
        options,
      ).status === 0
    );
  } finally {
    rmSync(probe, { recursive: true, force: true });
  }
}

export function validateArchiveDestination(projectRoot, archivePath) {
  if (typeof archivePath !== "string" || !path.isAbsolute(archivePath)) {
    throw new WorkflowError(
      `Use an absolute archive path. ${destinationHelp}`,
      64,
    );
  }
  const project = realpathSync(projectRoot);
  const outputStat = lstatSync(archivePath, { throwIfNoEntry: false });
  if (outputStat && !outputStat.isFile()) {
    throw new WorkflowError(
      `The archive destination must be a regular file, not a directory, symlink, or special file. ${destinationHelp}`,
      64,
    );
  }
  let destination;
  try {
    destination = resolveDestination(path.resolve(archivePath));
  } catch (error) {
    if (error instanceof WorkflowError) throw error;
    throw new WorkflowError(
      `The archive destination has an invalid ancestor. ${destinationHelp}`,
      64,
    );
  }
  if (inside(project, destination)) {
    const outputs = path.join(project, "outputs");
    if (
      destination === outputs ||
      !inside(outputs, destination) ||
      !ignoredOutput(project, destination)
    ) {
      throw new WorkflowError(destinationHelp, 64);
    }
  }
  return destination;
}
