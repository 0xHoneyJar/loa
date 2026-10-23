import { readProjectManifest, runPackageManager, selectPackageManager } from "./package-manager.mjs";
import {
  runMeasuredOperation,
  WorkflowError,
} from "./workflow-metrics.mjs";

// Build the project output; package-site creates its archive in a separate operation.
await runMeasuredOperation(() => {
  if (process.argv.length > 2) {
    throw new WorkflowError("build-site.mjs takes no arguments; it uses this project's package scripts.", 64);
  }
  const manifest = readProjectManifest();
  const manager = selectPackageManager(manifest);
  if (typeof manifest.scripts?.build !== "string" || !manifest.scripts.build.trim()) {
    throw new WorkflowError("This project has no build script; preserve its existing static or build workflow.");
  }
  return runPackageManager([manager.name, "run", "build"]);
});
