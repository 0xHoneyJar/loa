import { constants, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function detectExecutionProfile({ env = process.env } = {}) {
  return env.SITES_MANAGED_LINUX_CONTAINER === "1" ? "managed-linux" : "portable";
}

export function configureExecutionProfile(projectRoot, executionProfile = detectExecutionProfile()) {
  // Preserve other starters and older projects that do not consume this setting.
  if (!existsSync(path.join(projectRoot, "scripts/execution-profile.mjs"))) {
    return { executionProfile, configured: false };
  }
  // Resolve the workspace itself, but never follow repository-supplied links below it.
  const directory = path.join(realpathSync(projectRoot), ".sites-runtime");
  const directoryStat = lstatSync(directory, { throwIfNoEntry: false });
  if (directoryStat && !directoryStat.isDirectory()) {
    throw new Error(".sites-runtime must be a real directory, not a symlink.");
  }
  const file = path.join(directory, "execution-profile.json");
  const fileStat = lstatSync(file, { throwIfNoEntry: false });
  if (fileStat && !fileStat.isFile()) {
    throw new Error("execution-profile.json must be a regular file, not a symlink.");
  }
  const noFollow = constants.O_NOFOLLOW ?? 0;
  const contents = `${JSON.stringify({ executionProfile })}\n`;
  const changed = !fileStat || readFileSync(file, {
    encoding: "utf8", flag: constants.O_RDONLY | noFollow,
  }) !== contents;
  if (changed) {
    mkdirSync(directory, { recursive: true });
    writeFileSync(file, contents, {
      flag: constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | noFollow,
    });
  }
  return { executionProfile, configured: true, changed };
}

if (process.argv[1] && existsSync(process.argv[1]) && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 1 || args[0] !== "--detect")) {
    console.error("Use configure-execution-profile.mjs [--detect] in the Site checkout.");
    process.exitCode = 64;
  } else {
    const result = args.length
      ? { executionProfile: detectExecutionProfile() }
      : configureExecutionProfile(process.cwd());
    console.log(JSON.stringify(result));
  }
}
