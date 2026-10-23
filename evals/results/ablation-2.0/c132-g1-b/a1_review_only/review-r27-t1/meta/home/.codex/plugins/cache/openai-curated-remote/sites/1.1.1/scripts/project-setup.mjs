import {
  cpSync,
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { configureExecutionProfile } from "./configure-execution-profile.mjs";
import { markPendingPnpmBootstrap } from "./pnpm-bootstrap.mjs";
import { runMeasuredOperation, WorkflowError } from "./workflow-metrics.mjs";

// Copy and configure source; dependency installation is measured separately.
await runMeasuredOperation(() => {
  const options = parseSetupOptions(process.argv.slice(2));
  const destinationEntries = requireEmptyDestination();
  // Retained sources replace the starter; never layer one template over another.
  if (options.templateSource) {
    copyTemplate(options.templateSource, destinationEntries);
    console.log(JSON.stringify(configureExecutionProfile(process.cwd())));
    return { code: 0 };
  }
  const starter = options.starter ?? "vinext";
  copyTemplate(
    fileURLToPath(
      new URL(
        `../skills/sites/templates/${starter}-starter/`,
        import.meta.url,
      ),
    ),
    destinationEntries,
  );
  if (starter === "worker-esm") return { code: 0 };

  const profile = configureExecutionProfile(process.cwd());
  if (profile.executionProfile === "managed-linux")
    markPendingPnpmBootstrap(process.cwd());
  console.log(JSON.stringify(profile));
  return { code: 0 };
});

function parseSetupOptions(argv) {
  const optionNames = new Map([
    ["--template-source", "templateSource"],
    ["--starter", "starter"],
  ]);
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = optionNames.get(argv[index]);
    const value = argv[index + 1];
    if (
      !name ||
      !value ||
      value.startsWith("--") ||
      options[name] !== undefined
    ) {
      throw new WorkflowError(
        "Invalid setup option; use the documented project-setup.mjs options.",
        64,
      );
    }
    options[name] = value;
  }
  if (options.templateSource) {
    if (Object.keys(options).length !== 1) {
      throw new WorkflowError(
        "--template-source cannot be combined with --starter.",
        64,
      );
    }
  } else if (
    options.starter &&
    !["vinext", "worker-esm"].includes(options.starter)
  ) {
    throw new WorkflowError("--starter must be vinext or worker-esm.", 64);
  }
  return options;
}

function requireEmptyDestination() {
  const entries = readdirSync(".");
  const allowed = new Set([
    ".git",
    ".agents",
    ".codex",
    ".DS_Store",
    "work",
    "outputs",
  ]);
  if (entries.some((name) => !allowed.has(name))) {
    throw new WorkflowError(
      "Project setup requires an empty checkout; existing files were not changed.",
      2,
    );
  }
  return entries;
}

function copyTemplate(source, destinationEntries) {
  if (!path.isAbsolute(source)) {
    throw new WorkflowError(
      "--template-source must be an absolute directory.",
      64,
    );
  }
  let resolved;
  try {
    if (lstatSync(source).isSymbolicLink()) {
      throw new WorkflowError("Template sources must not be symlinks.");
    }
    resolved = realpathSync(source);
    if (!statSync(resolved).isDirectory()) throw new Error();
  } catch (error) {
    if (error instanceof WorkflowError) throw error;
    throw new WorkflowError(
      "The template source must be an existing directory.",
    );
  }
  const destination = realpathSync(".");
  const relative = path.relative(resolved, destination);
  if (
    !relative ||
    (!relative.startsWith(`..${path.sep}`) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  ) {
    throw new WorkflowError(
      "The destination cannot be inside its template source.",
    );
  }
  const entries = readdirSync(resolved);
  if (entries.some((name) => destinationEntries.includes(name))) {
    throw new WorkflowError(
      "The template would overwrite existing checkout metadata.",
    );
  }
  // Validate the whole tree before the first copy. Unsafe source must leave the
  // destination untouched and must not carry another Site's identity forward.
  validateTemplateTree(resolved);
  for (const entry of entries) {
    cpSync(path.join(resolved, entry), path.join(destination, entry), {
      recursive: true,
      force: false,
      errorOnExist: true,
      verbatimSymlinks: true,
    });
  }
  return { code: 0 };
}

function validateTemplateTree(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.toLowerCase() === ".git" || entry.isSymbolicLink()) {
      throw new WorkflowError(
        "Templates must not contain Git metadata or symlinks.",
      );
    }
    if (entry.isDirectory())
      validateTemplateTree(path.join(directory, entry.name));
    else if (!entry.isFile())
      throw new WorkflowError(
        "Templates may contain only regular files and directories.",
      );
  }
  const hosting = path.join(directory, ".openai", "hosting.json");
  if (!existsSync(hosting)) return;
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(hosting, "utf8"));
  } catch {
    throw new WorkflowError(
      "The template hosting manifest must be valid JSON.",
    );
  }
  const projectId = manifest?.project_id;
  if (projectId !== undefined && projectId !== null && projectId !== "") {
    throw new WorkflowError(
      "A retained template must not contain another Site's project_id.",
    );
  }
}
