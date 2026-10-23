import { execFile } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { validateArchiveDestination } from "./archive-path.mjs";
import { runMeasuredOperation, WorkflowError } from "./workflow-metrics.mjs";

function capture(executable, args) {
  return new Promise((resolve, reject) => {
    let receivedSignal;
    const handlers = new Map(
      ["SIGINT", "SIGHUP", "SIGTERM"].map((signal) => [
        signal,
        () => {
          receivedSignal ??= signal;
        },
      ]),
    );
    execFile(
      executable,
      args,
      { encoding: "utf8", windowsHide: true, maxBuffer: 16 * 1024 * 1024 },
      (error, stdout, stderr) => {
        for (const [signal, handler] of handlers)
          process.removeListener(signal, handler);
        if (error || receivedSignal) {
          const failure = new WorkflowError(
            stderr?.trim() ||
              (error?.code === "ENOENT"
                ? `Unable to start ${path.basename(
                    executable,
                  )}; Sites packaging requires Node.js and tar on PATH.`
                : "Unable to package the Site archive."),
            Number.isInteger(error?.code) ? error.code : 1,
          );
          failure.signal = receivedSignal ?? error?.signal;
          reject(failure);
        } else resolve(stdout);
      },
    );
    // Exec owns group cancellation. Observe it and finish cleanup after the
    // child exits; do not relay a signal a second time to the child process.
    for (const [signal, handler] of handlers) process.on(signal, handler);
  });
}

export async function packageSite(projectRoot, archivePath) {
  const project = realpathSync(projectRoot);
  const archive = validateArchiveDestination(project, archivePath);
  const hostingPath = path.join(project, ".openai/hosting.json");
  if (!existsSync(hostingPath))
    throw new WorkflowError("Missing .openai/hosting.json", 2);
  const stage = mkdtempSync(path.join(tmpdir(), "sites-package-"));
  let archiveStage;
  try {
    // Keep the shared remote-build preparer's validation and static normalization.
    const prepare = fileURLToPath(
      new URL(
        "../skills/sites/scripts/prepare-site-build.cjs",
        import.meta.url,
      ),
    );
    const kind = (
      await capture(process.execPath, [
        prepare,
        project,
        path.join(stage, "dist"),
      ])
    ).trim();
    const read = (filename) => JSON.parse(readFileSync(filename, "utf8"));
    const source = read(hostingPath);
    const builtPath = path.join(project, "dist/.openai/hosting.json");
    const built = existsSync(builtPath) ? read(builtPath) : {};
    if (
      source.artifact_metadata != null &&
      built.artifact_metadata != null &&
      !isDeepStrictEqual(source.artifact_metadata, built.artifact_metadata)
    ) {
      throw new WorkflowError(
        "Conflicting artifact_metadata in source and built hosting manifests; rebuild with consistent attribution before packaging.",
      );
    }
    const stagedPath = path.join(stage, "dist/.openai/hosting.json");
    const staged = kind === "worker" ? source : read(stagedPath);
    const attribution = built.artifact_metadata ?? source.artifact_metadata;
    if (attribution != null) staged.artifact_metadata = attribution;
    mkdirSync(path.dirname(stagedPath), { recursive: true });
    writeFileSync(stagedPath, `${JSON.stringify(staged, null, 2)}\n`);
    const migrations = path.join(project, "drizzle");
    if (existsSync(migrations)) {
      cpSync(migrations, path.join(stage, "dist/.openai/drizzle"), {
        recursive: true,
        dereference: false,
      });
    }

    // Validate again after preparation, and write privately before replacing the
    // destination. Failed packaging leaves an existing archive unchanged.
    if (validateArchiveDestination(project, archivePath) !== archive) {
      throw new WorkflowError(
        "The archive destination changed during packaging; retry with a stable path.",
      );
    }
    mkdirSync(path.dirname(archive), { recursive: true });
    archiveStage = mkdtempSync(
      path.join(path.dirname(archive), ".sites-archive-"),
    );
    const stagedArchive = path.join(archiveStage, "site.tar.gz");
    const tar = process.platform === "win32" ? "tar.exe" : "tar";
    await capture(tar, ["-C", stage, "-czf", stagedArchive, "dist"]);
    const entries = (await capture(tar, ["-tzf", stagedArchive])).split(
      /\r?\n/,
    );
    if (!entries.includes("dist/.openai/hosting.json")) {
      throw new WorkflowError(
        "The Site archive is missing dist/.openai/hosting.json.",
      );
    }
    if (validateArchiveDestination(project, archivePath) !== archive) {
      throw new WorkflowError(
        "The archive destination changed during packaging; retry with a stable path.",
      );
    }
    renameSync(stagedArchive, archive);
    return archive;
  } finally {
    if (archiveStage) rmSync(archiveStage, { recursive: true, force: true });
    rmSync(stage, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  existsSync(process.argv[1]) &&
  import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href
) {
  await runMeasuredOperation(async () => {
    try {
      const [project, archive, ...extra] = process.argv.slice(2);
      if (!project || !archive || extra.length) {
        throw new WorkflowError(
          "Usage: package-site.mjs PROJECT_DIR ARCHIVE_PATH",
          64,
        );
      }
      console.log(await packageSite(project, archive));
      return { code: 0 };
    } catch (error) {
      process.stderr.write(
        `${error.message || "Unable to package the Site archive."}\n`,
      );
      return { code: error.exitCode ?? 1, signal: error.signal };
    }
  });
}
