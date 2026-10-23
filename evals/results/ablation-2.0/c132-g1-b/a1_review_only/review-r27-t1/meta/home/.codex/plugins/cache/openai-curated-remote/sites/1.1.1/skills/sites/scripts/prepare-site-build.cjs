// Shared by Sites remote builds and all three plugin packagers; keep copies byte-identical.
const fs = require("node:fs");
const path = require("node:path");

const staticRoots = ["dist/client", ".output/public", "out", "build", "dist"];

function assertInsideProject(project, filename) {
  const relative = path.relative(
    fs.realpathSync(project),
    fs.realpathSync(filename),
  );
  if (
    relative === ".." ||
    relative.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relative)
  ) {
    throw new Error("Build output and metadata must stay inside the project");
  }
}

function assertRegularTree(filename) {
  const stat = fs.lstatSync(filename);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(filename))
      assertRegularTree(path.join(filename, entry));
  } else if (!stat.isFile()) {
    throw new Error(
      `Build output contains a symlink or special file: ${filename}`,
    );
  }
}

function readConfig(project, relativePath) {
  const filename = path.join(project, relativePath);
  if (!fs.existsSync(filename)) return undefined;
  assertInsideProject(project, filename);
  if (!fs.lstatSync(filename).isFile())
    throw new Error(`Not a regular file: ${filename}`);
  let config;
  try {
    config = JSON.parse(fs.readFileSync(filename, "utf8"));
  } catch {
    throw new Error(`Invalid JSON in ${filename}`);
  }
  if (!config || Array.isArray(config) || typeof config !== "object") {
    throw new Error(`Expected an object in ${filename}`);
  }
  return config;
}

function hasMigrations(directory) {
  if (!fs.existsSync(directory)) return false;
  if (fs.lstatSync(directory).isSymbolicLink()) return true;
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .some(
      (entry) =>
        entry.isSymbolicLink() ||
        (entry.isDirectory()
          ? hasMigrations(path.join(directory, entry.name))
          : entry.name.endsWith(".sql")),
    );
}

function prepare(project, destination, originalProject = project) {
  const builtHosting = readConfig(project, "dist/.openai/hosting.json");
  const sourceHosting = readConfig(project, ".openai/hosting.json");
  const originalHosting =
    originalProject === project
      ? sourceHosting
      : readConfig(originalProject, ".openai/hosting.json");
  const legacyHosting = readConfig(project, "dist/_appgen_meta/appgarden.json");
  const sourceDrizzle = path.join(project, "drizzle");
  if (fs.existsSync(sourceDrizzle)) {
    assertInsideProject(project, sourceDrizzle);
    assertRegularTree(sourceDrizzle);
  }
  const hosting = sourceHosting ?? builtHosting ?? originalHosting;
  const staticConfig = hosting?.static;
  if (
    staticConfig != null &&
    (typeof staticConfig !== "object" ||
      Array.isArray(staticConfig) ||
      !staticRoots.includes(
        "directory" in staticConfig ? staticConfig.directory : "dist",
      ) ||
      Object.keys(staticConfig).some(
        (key) => !["directory", "not_found_handling"].includes(key),
      ) ||
      (staticConfig.not_found_handling != null &&
        !["none", "404-page", "single-page-application"].includes(
          staticConfig.not_found_handling,
        )))
  )
    throw new Error("Invalid static configuration in .openai/hosting.json");

  const isStatic = staticConfig != null;
  if (!isStatic && builtHosting?.static != null)
    throw new Error(
      "Worker builds must not retain static configuration in dist/.openai/hosting.json",
    );
  const inputRoot = isStatic ? staticConfig.directory ?? "dist" : "dist";
  const entrypoint = isStatic ? `${inputRoot}/index.html` : "dist/server/index.js";
  if (
    !fs.statSync(path.join(project, entrypoint), { throwIfNoEntry: false })?.isFile()
  )
    throw new Error(`Missing ${entrypoint}`);
  if (
    isStatic &&
    ([builtHosting, sourceHosting, originalHosting, legacyHosting].some(
      (config) =>
        config?.d1 != null ||
        config?.r2 != null ||
        config?.capabilities?.length,
    ) ||
      hasMigrations(path.join(originalProject, "drizzle")) ||
      hasMigrations(path.join(project, "drizzle")) ||
      hasMigrations(path.join(project, "dist/.openai/drizzle")) ||
      hasMigrations(path.join(project, "dist/_appgen_meta/drizzle")))
  )
    throw new Error(
      "Static builds cannot use runtime bindings, capabilities, or database migrations",
    );

  const input = path.join(project, inputRoot);
  if (!fs.lstatSync(input).isDirectory())
    throw new Error("Build output must be a directory, not a symlink");
  assertInsideProject(project, input);
  assertRegularTree(input);
  const relativeDestination = path.relative(input, destination);
  if (
    !relativeDestination.startsWith(`..${path.sep}`) &&
    relativeDestination !== ".." &&
    !path.isAbsolute(relativeDestination)
  ) {
    throw new Error("Build destination must be outside its input directory");
  }
  fs.rmSync(destination, { recursive: true, force: true });
  fs.cpSync(input, destination, { recursive: true, dereference: false });
  for (const sidecar of [".openai", "_appgen_meta"]) {
    const source = path.join(project, "dist", sidecar);
    if (inputRoot !== "dist" && fs.existsSync(source)) {
      assertInsideProject(project, source);
      assertRegularTree(source);
      fs.cpSync(source, path.join(destination, sidecar), {
        recursive: true,
        dereference: false,
      });
    }
  }
  if (isStatic) {
    fs.mkdirSync(path.join(destination, ".openai"), { recursive: true });
    fs.writeFileSync(
      path.join(destination, ".openai/hosting.json"),
      JSON.stringify({
        ...hosting,
        static: { ...staticConfig, directory: "dist" },
      }) + "\n",
    );
  } else if (
    originalProject !== project &&
    !fs.existsSync(path.join(destination, ".openai/hosting.json")) &&
    !fs.existsSync(path.join(destination, "_appgen_meta/appgarden.json")) &&
    originalHosting &&
    !hasMigrations(path.join(originalProject, "drizzle"))
  ) {
    // Only a separate source copy can prove no migrations were lost by the build.
    fs.mkdirSync(path.join(destination, ".openai"), { recursive: true });
    fs.copyFileSync(
      path.join(originalProject, ".openai/hosting.json"),
      path.join(destination, ".openai/hosting.json"),
    );
  }
  return isStatic ? "static" : "worker";
}

try {
  const [project, destination, originalProject] = process.argv.slice(2);
  if (!project || !destination)
    throw new Error("Expected PROJECT_DIR and DESTINATION_DIST");
  console.log(
    prepare(
      path.resolve(project),
      path.resolve(destination),
      originalProject && path.resolve(originalProject),
    ),
  );
} catch (error) {
  console.error(
    error instanceof Error
      ? error.message
      : "Unable to prepare Sites build output",
  );
  process.exitCode = 1;
}
